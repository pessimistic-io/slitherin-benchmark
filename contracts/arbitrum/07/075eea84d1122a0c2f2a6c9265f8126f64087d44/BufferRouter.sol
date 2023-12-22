// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.4;

import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./draft-IERC20Permit.sol";
import "./Interfaces.sol";
import "./ECDSA.sol";
import "./Validator.sol";

/**
 * @author Heisenberg
 * @notice Buffer Options Router Contract
 */
contract BufferRouter is AccessControl, IBufferRouter {
    using SafeERC20 for ERC20;
    uint16 public MAX_DELAY_FOR_OPEN_TRADE = 1 minutes;
    uint16 public MAX_DELAY_FOR_ASSET_PRICE = 1 minutes;

    address public publisher;
    address public sfPublisher;
    address public admin;
    IAccountRegistrar public accountRegistrar;

    mapping(uint256 => QueuedTrade) public queuedTrades;
    mapping(address => bool) public contractRegistry;
    mapping(address => bool) public isKeeper;
    mapping(bytes => bool) public prevSignature;
    mapping(address => mapping(uint256 => OptionInfo)) public optionIdMapping;

    constructor(
        address _publisher,
        address _sfPublisher,
        address _admin,
        address _accountRegistrar
    ) {
        publisher = _publisher;
        sfPublisher = _sfPublisher;
        admin = _admin;
        accountRegistrar = IAccountRegistrar(_accountRegistrar);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /************************************************
     *  ADMIN ONLY FUNCTIONS
     ***********************************************/

    function setContractRegistry(
        address targetContract,
        bool register
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        contractRegistry[targetContract] = register;

        emit ContractRegistryUpdated(targetContract, register);
    }

    function setKeeper(
        address _keeper,
        bool _isActive
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isKeeper[_keeper] = _isActive;
    }

    /************************************************
     *  KEEPER ONLY FUNCTIONS
     ***********************************************/

    function approveViaSignature(
        address tokenX,
        address user,
        uint256 queueId,
        Permit memory permit
    ) internal returns (bool) {
        IERC20Permit token = IERC20Permit(tokenX);
        uint256 nonceBefore = token.nonces(user);
        try
            token.permit(
                user,
                address(this),
                permit.value,
                permit.deadline,
                permit.v,
                permit.r,
                permit.s
            )
        {} catch Error(string memory reason) {
            emit FailResolve(queueId, reason);
            return false;
        }
        uint256 nonceAfter = token.nonces(user);
        if (nonceAfter != nonceBefore + 1) {
            emit FailResolve(queueId, "Router: Permit did not succeed");
            return false;
        }
        emit ApproveRouter(
            user,
            nonceBefore,
            permit.value,
            permit.deadline,
            tokenX
        );
        return true;
    }

    function revokeApprovals(RevokeParams[] calldata revokeParams) external {
        for (uint256 index = 0; index < revokeParams.length; index++) {
            RevokeParams memory params = revokeParams[index];
            IERC20Permit token = IERC20Permit(params.tokenX);
            uint256 nonceBefore = token.nonces(params.user);
            try
                token.permit(
                    params.user,
                    address(this),
                    params.permit.value,
                    params.permit.deadline,
                    params.permit.v,
                    params.permit.r,
                    params.permit.s
                )
            {} catch Error(string memory reason) {
                emit FailRevoke(params.user, params.tokenX, reason);
            }
            uint256 nonceAfter = token.nonces(params.user);
            if (nonceAfter != nonceBefore + 1) {
                emit FailRevoke(
                    params.user,
                    params.tokenX,
                    "Router: Permit did not succeed"
                );
            }
            emit RevokeRouter(
                params.user,
                nonceBefore,
                params.permit.value,
                params.permit.deadline,
                params.tokenX
            );
        }
    }

    function openTrades(OpenTxn[] calldata params) external {
        _validateKeeper();
        for (uint32 index = 0; index < params.length; index++) {
            TradeParams memory currentParams = params[index].tradeParams;
            address user = params[index].user;
            IBufferBinaryOptions optionsContract = IBufferBinaryOptions(
                currentParams.targetContract
            );
            IOptionsConfig config = IOptionsConfig(optionsContract.config());

            ERC20 tokenX = ERC20(optionsContract.tokenX());
            Permit memory permit = params[index].permit;
            uint256 amountToPay = currentParams.totalFee + config.platformFee();
            if (tokenX.balanceOf(user) < amountToPay) {
                emit FailResolve(
                    currentParams.queueId,
                    "Router: Insufficient balance"
                );
                continue;
            }
            if (
                (tokenX.allowance(user, address(this)) < amountToPay) &&
                (!permit.shouldApprove)
            ) {
                emit FailResolve(
                    currentParams.queueId,
                    "Router: Incorrect allowance"
                );
                continue;
            } else if (permit.shouldApprove) {
                bool success = approveViaSignature(
                    address(optionsContract.tokenX()),
                    user,
                    currentParams.queueId,
                    permit
                );
                if (!success) continue;
            }
            if (params[index].register.shouldRegister) {
                try
                    accountRegistrar.registerAccount(
                        params[index].register.oneCT,
                        user,
                        params[index].register.signature
                    )
                {} catch Error(string memory reason) {
                    emit FailResolve(
                        currentParams.queueId,
                        "Router: Registration failed"
                    );
                    continue;
                }
            }

            (address signer, uint256 nonce) = getAccountMapping(user);
            uint256 safeStrike = getSafeStrike(
                currentParams.price,
                currentParams.isAbove,
                config,
                optionsContract
            );

            (bool isValid, string memory errorResaon) = verifyTrade(
                currentParams,
                user,
                signer,
                optionsContract,
                safeStrike
            );
            if (!isValid) {
                emit FailResolve(currentParams.queueId, errorResaon);
                continue;
            }
            _openTrade(
                currentParams,
                user,
                signer,
                nonce,
                optionsContract,
                config,
                safeStrike
            );
        }
    }

    function closeAnytime(CloseAnytimeParams[] calldata closeParams) external {
        _validateKeeper();
        for (uint32 index = 0; index < closeParams.length; index++) {
            CloseAnytimeParams memory closeParam = closeParams[index];
            CloseTradeParams memory params = closeParam.closeTradeParams;
            OptionInfo memory optionInfo = optionIdMapping[
                params.targetContract
            ][params.optionId];
            IBufferBinaryOptions optionsContract = IBufferBinaryOptions(
                params.targetContract
            );
            IBufferRouter.SignInfo memory publisherSignInfo = params
                .publisherSignInfo;
            QueuedTrade memory queuedTrade = queuedTrades[optionInfo.queueId];
            address owner = optionsContract.ownerOf(params.optionId);
            (, , , , , , , uint256 createdAt) = optionsContract.options(
                params.optionId
            );
            if (closeParam.register.shouldRegister) {
                try
                    accountRegistrar.registerAccount(
                        closeParam.register.oneCT,
                        owner,
                        closeParam.register.signature
                    )
                {} catch Error(string memory reason) {
                    emit FailUnlock(
                        params.optionId,
                        params.targetContract,
                        reason
                    );
                    continue;
                }
            }
            if (
                !queuedTrade.isEarlyCloseAllowed ||
                (block.timestamp - createdAt <
                    IOptionsConfig(optionsContract.config())
                        .earlyCloseThreshold())
            ) {
                emit FailUnlock(
                    params.optionId,
                    params.targetContract,
                    "Router: Early close is not allowed"
                );
                continue;
            }
            (address signer, ) = getAccountMapping(queuedTrade.user);

            bool isUserSignValid = Validator.verifyCloseAnytime(
                optionsContract.assetPair(),
                closeParam.userSignInfo.timestamp,
                params.optionId,
                closeParam.userSignInfo.signature,
                signer
            );

            bool isSignerVerifed = Validator.verifyPublisher(
                optionsContract.assetPair(),
                publisherSignInfo.timestamp,
                params.closingPrice,
                publisherSignInfo.signature,
                publisher
            );

            // Silently fail if the signature doesn't match
            if (!isSignerVerifed) {
                emit FailUnlock(
                    params.optionId,
                    params.targetContract,
                    "Router: Publisher signature didn't match"
                );
                continue;
            }
            if (!isUserSignValid) {
                emit FailUnlock(
                    params.optionId,
                    params.targetContract,
                    "Router: User signature didn't match"
                );
                continue;
            }

            if (
                !Validator.verifyMarketDirection(
                    params,
                    queuedTrade,
                    optionInfo.signer
                )
            ) {
                emit FailUnlock(
                    params.optionId,
                    params.targetContract,
                    "Router: Wrong market direction"
                );
                continue;
            }

            try
                optionsContract.unlock(
                    params.optionId,
                    params.closingPrice,
                    publisherSignInfo.timestamp,
                    params.isAbove
                )
            {} catch Error(string memory reason) {
                emit FailUnlock(params.optionId, params.targetContract, reason);
                continue;
            }
        }
    }

    function executeOptions(CloseTradeParams[] calldata optionData) external {
        _validateKeeper();

        uint32 arrayLength = uint32(optionData.length);
        for (uint32 i = 0; i < arrayLength; i++) {
            CloseTradeParams memory params = optionData[i];
            OptionInfo memory optionInfo = optionIdMapping[
                params.targetContract
            ][params.optionId];

            IBufferBinaryOptions optionsContract = IBufferBinaryOptions(
                params.targetContract
            );
            (, , , , , uint256 expiration, , ) = optionsContract.options(
                params.optionId
            );
            IBufferRouter.SignInfo memory signInfo = params.publisherSignInfo;

            bool isSignerVerifed = Validator.verifyPublisher(
                optionsContract.assetPair(),
                signInfo.timestamp,
                params.closingPrice,
                signInfo.signature,
                publisher
            );

            // Silently fail if the signature doesn't match
            if (!isSignerVerifed) {
                emit FailUnlock(
                    params.optionId,
                    params.targetContract,
                    "Router: Signature didn't match"
                );
                continue;
            }

            QueuedTrade memory queuedTrade = queuedTrades[optionInfo.queueId];

            if (
                !Validator.verifyMarketDirection(
                    params,
                    queuedTrade,
                    optionInfo.signer
                )
            ) {
                emit FailUnlock(
                    params.optionId,
                    params.targetContract,
                    "Router: Wrong market direction"
                );
                continue;
            }

            // Silently fail if the timestamp of the signature is wrong
            if (expiration != signInfo.timestamp) {
                emit FailUnlock(
                    params.optionId,
                    params.targetContract,
                    "Router: Wrong price"
                );
                continue;
            } else if (expiration > block.timestamp) {
                emit FailUnlock(
                    params.optionId,
                    params.targetContract,
                    "Router: Wrong closing time"
                );
                continue;
            }

            try
                optionsContract.unlock(
                    params.optionId,
                    params.closingPrice,
                    expiration,
                    params.isAbove
                )
            {} catch Error(string memory reason) {
                emit FailUnlock(params.optionId, params.targetContract, reason);
                continue;
            }
        }
    }

    /************************************************
     *  INTERNAL FUNCTIONS
     ***********************************************/
    function _validateKeeper() private view {
        require(isKeeper[msg.sender], "Keeper: forbidden");
    }

    function getAccountMapping(
        address user
    ) public view returns (address, uint256) {
        (address oneCT, uint256 nonce) = accountRegistrar.accountMapping(user);
        return (oneCT, nonce);
    }

    function getSpread(
        uint256 strike,
        bool isAbove,
        IOptionsConfig config,
        IBufferBinaryOptions optionsContract
    ) public view returns (uint256) {
        uint256 spreadConfig1 = config.spreadConfig1();
        uint256 spreadConfig2 = config.spreadConfig2();
        uint256 m = (spreadConfig2 - spreadConfig1) / 1350;
        uint256 c = (22 * spreadConfig1 - 5 * spreadConfig2) / 27;
        uint256 spread = (m * config.iv()) + c;

        spread =
            ((spread *
                (config.spreadFactor()) *
                optionsContract.totalMarketOI()) /
                (1e3 * optionsContract.getMaxOI())) +
            spread;
        return spread;
    }

    function getSafeStrike(
        uint256 strike,
        bool isAbove,
        IOptionsConfig config,
        IBufferBinaryOptions optionsContract
    ) public view returns (uint256) {
        uint256 spread = getSpread(strike, isAbove, config, optionsContract);
        return
            isAbove
                ? (strike * (1e8 + spread)) / 1e8
                : (strike * (1e8 - spread)) / 1e8;
    }

    function verifyTrade(
        TradeParams memory params,
        address user,
        address tradeSigner,
        IBufferBinaryOptions optionsContract,
        uint256 safeStrike
    ) internal view returns (bool, string memory) {
        SignInfo memory settlementFeeSignInfo = params.settlementFeeSignInfo;
        SignInfo memory publisherSignInfo = params.publisherSignInfo;
        SignInfo memory userSignInfo = params.userSignInfo;

        if (!contractRegistry[params.targetContract]) {
            return (false, "Router: Unauthorized contract");
        }
        if (queuedTrades[params.queueId].isTradeResolved) {
            return (false, "Router: Trade has already been opened");
        }
        if (prevSignature[userSignInfo.signature]) {
            return (false, "Router: Signature already used");
        }
        if (!Validator.verifyUserTradeParams(params, user, tradeSigner)) {
            return (false, "Router: User signature didn't match");
        }
        if (
            !Validator.verifySettlementFee(
                optionsContract.assetPair(),
                params.settlementFee,
                settlementFeeSignInfo.timestamp,
                settlementFeeSignInfo.signature,
                sfPublisher
            )
        ) {
            return (false, "Router: Wrong settlement fee");
        }
        if (
            !Validator.verifyPublisher(
                optionsContract.assetPair(),
                publisherSignInfo.timestamp,
                params.price,
                publisherSignInfo.signature,
                publisher
            )
        ) {
            return (false, "Router: Publisher signature didn't match");
        }
        if (settlementFeeSignInfo.timestamp < block.timestamp) {
            return (false, "Router: Settlement fee has expired");
        }
        if (!params.isLimitOrder) {
            if (
                block.timestamp - userSignInfo.timestamp >
                MAX_DELAY_FOR_OPEN_TRADE
            ) {
                return (false, "Router: Invalid user signature timestamp");
            }
            if (params.settlementFee != params.userSignedSettlementFee) {
                return (false, "Router: Settlement fee is not valid");
            }
        } else {
            if (block.timestamp > params.limitOrderExpiry) {
                return (false, "Router: Limit order has already expired");
            }
            if (params.settlementFee > params.userSignedSettlementFee) {
                return (false, "Router: Settlement fee is not valid");
            }
        }
        if (
            block.timestamp - publisherSignInfo.timestamp >
            MAX_DELAY_FOR_ASSET_PRICE
        ) {
            return (false, "Router: Invalid publisher signature timestamp");
        }
        if (
            !optionsContract.isStrikeValid(
                params.slippage,
                safeStrike,
                params.strike
            )
        ) {
            return (false, "Router: Slippage limit exceeded");
        }
        return (true, "");
    }

    function _openTrade(
        TradeParams memory params,
        address user,
        address tradeSigner,
        uint256 nonce,
        IBufferBinaryOptions optionsContract,
        IOptionsConfig config,
        uint256 safeStrike
    ) internal {
        // Check all the parameters and compute the amount and revised fee
        uint256 amount;
        uint256 revisedFee;
        IBufferBinaryOptions.OptionParams
            memory optionParams = IBufferBinaryOptions.OptionParams(
                params.strike,
                0,
                params.period,
                params.allowPartialFill,
                params.totalFee,
                user,
                params.referralCode,
                params.settlementFee
            );

        try
            optionsContract.evaluateParams(optionParams, params.slippage)
        returns (uint256 _amount, uint256 _revisedFee) {
            (amount, revisedFee) = (_amount, _revisedFee);
        } catch Error(string memory reason) {
            emit CancelTrade(user, params.queueId, reason);
            return;
        }

        // Transfer the fee specified from the user to options contract.
        // User has to approve first inorder to execute this function
        ERC20 tokenX = ERC20(optionsContract.tokenX());

        tokenX.safeTransferFrom(user, admin, config.platformFee());
        tokenX.safeTransferFrom(user, params.targetContract, revisedFee);

        optionParams.strike = safeStrike;
        optionParams.amount = amount;
        optionParams.totalFee = revisedFee;

        uint256 optionId = optionsContract.createFromRouter(
            optionParams,
            params.publisherSignInfo.timestamp
        );
        queuedTrades[params.queueId] = QueuedTrade({
            user: user,
            targetContract: params.targetContract,
            strike: params.strike,
            slippage: params.slippage,
            period: params.period,
            allowPartialFill: params.allowPartialFill,
            totalFee: params.totalFee,
            referralCode: params.referralCode,
            settlementFee: params.userSignedSettlementFee,
            isLimitOrder: params.isLimitOrder,
            isTradeResolved: true,
            optionId: optionId,
            isEarlyCloseAllowed: config.isEarlyCloseAllowed(),
            isAbove: params.isAbove
        });
        optionIdMapping[params.targetContract][optionId] = OptionInfo({
            queueId: params.queueId,
            signer: tradeSigner,
            nonce: nonce
        });
        prevSignature[params.userSignInfo.signature] = true;

        emit OpenTrade(user, params.queueId, optionId, params.targetContract);
    }
}

