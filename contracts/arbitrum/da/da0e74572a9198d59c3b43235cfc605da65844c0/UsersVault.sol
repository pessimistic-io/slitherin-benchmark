// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20Upgradeable} from "./ERC20_IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "./IERC20MetadataUpgradeable.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";

import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";

import {BaseVault} from "./BaseVault.sol";

import {IUsersVault} from "./IUsersVault.sol";
import {ITraderWallet} from "./ITraderWallet.sol";
import {IContractsFactory} from "./IContractsFactory.sol";
import {IAdaptersRegistry} from "./IAdaptersRegistry.sol";
import {IAdapter} from "./IAdapter.sol";
import {IDynamicValuation} from "./IDynamicValuation.sol";
import "./IAdapter.sol";
import {ILens} from "./ILens.sol";

contract UsersVault is ERC20Upgradeable, BaseVault, IUsersVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public override traderWalletAddress;

    // Total amount of total deposit assets in mapped round
    uint256 public override pendingDepositAssets;

    // Total amount of total withdrawal shares in mapped round
    uint256 public override pendingWithdrawShares;

    uint256 public override processedWithdrawAssets;

    uint256 public override kunjiFeesAssets;

    // rollover time control
    uint256 public emergencyPeriod;
    bool public isEmergencyOpen;

    // slippage control
    uint256 public defaultSlippagePercent;
    uint256 public slippageStepPercent;
    uint256 public currentSlippage;

    // ratio per round
    mapping(uint256 => uint256) public assetsPerShareXRound;

    mapping(address => UserData) private _userData;
    mapping(uint256 => uint256) private _underlyingPriceXRound;

    modifier onlyTraderWallet() {
        if (msg.sender != traderWalletAddress) revert UserNotAllowed();
        _;
    }

    modifier onlyValidInvestors(address account) {
        if (
            !IContractsFactory(contractsFactoryAddress).allowedInvestors(
                account
            )
        ) revert UserNotAllowed();
        _;
    }

    function initialize(
        address _underlyingTokenAddress,
        address _traderWalletAddress,
        address _ownerAddress,
        string memory _sharesName,
        string memory _sharesSymbol
    ) external virtual override initializer {
        __UsersVault_init(
            _underlyingTokenAddress,
            _traderWalletAddress,
            _ownerAddress,
            _sharesName,
            _sharesSymbol
        );
    }

    function __UsersVault_init(
        address _underlyingTokenAddress,
        address _traderWalletAddress,
        address _ownerAddress,
        string memory _sharesName,
        string memory _sharesSymbol
    ) internal onlyInitializing {
        __BaseVault_init(_underlyingTokenAddress, _ownerAddress);
        __ERC20_init(_sharesName, _sharesSymbol);

        __UsersVault_init_unchained(_traderWalletAddress);
    }

    function __UsersVault_init_unchained(
        address _traderWalletAddress
    ) internal onlyInitializing {
        _checkZeroAddress(_traderWalletAddress, "_traderWalletAddress");

        traderWalletAddress = _traderWalletAddress;

        emergencyPeriod = 15 hours; // 15h
        defaultSlippagePercent = 150; // 1.5%
        slippageStepPercent = 100; // 1%
        currentSlippage = defaultSlippagePercent;
    }

    /// @notice Increase decimals to 30 for enhanced precision
    function decimals() public view virtual override returns (uint8) {
        return 30;
    }

    function collectFees(uint256 amount) external override onlyOwner {
        uint256 _kunjiFeesAssets = kunjiFeesAssets;

        if (amount > _kunjiFeesAssets) {
            revert TooBigAmount();
        }

        kunjiFeesAssets = _kunjiFeesAssets - amount;

        address feeReceiver = IContractsFactory(contractsFactoryAddress)
            .feeReceiver();
        IERC20Upgradeable(underlyingTokenAddress).safeTransfer(feeReceiver, amount);
    }

    function setAdapterAllowanceOnToken(
        uint256 _protocolId,
        address _tokenAddress,
        bool _revoke
    ) external override onlyOwner {
        address _traderWalletAddress = traderWalletAddress;
        if (
            !ITraderWallet(_traderWalletAddress).isTraderSelectedProtocol(
                _protocolId
            )
        ) {
            revert InvalidProtocol();
        }
        if (
            !ITraderWallet(_traderWalletAddress).isAllowedTradeToken(
                _tokenAddress
            )
        ) {
            revert InvalidToken();
        }

        address adapterAddress = _getAdapterAddress(_protocolId);

        uint256 amount;
        if (!_revoke) amount = type(uint256).max;

        IERC20Upgradeable(_tokenAddress).forceApprove(adapterAddress, amount);
    }

    function userDeposit(
        uint256 _amount
    ) external override {
        if (_amount == 0) revert ZeroAmount();

        UserData memory data = _updateUserData(msg.sender);

        _userData[msg.sender].pendingDepositAssets =
            data.pendingDepositAssets +
            _amount;

        pendingDepositAssets += _amount;

        IERC20Upgradeable(underlyingTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        emit UserDeposited(_msgSender(), _amount, currentRound);
    }

    function withdrawRequest(uint256 _sharesAmount) external override {
        if (_sharesAmount == 0) revert ZeroAmount();

        UserData memory data = _updateUserData(msg.sender);
        _userData[msg.sender].pendingWithdrawShares =
            data.pendingWithdrawShares +
            _sharesAmount;

        pendingWithdrawShares += _sharesAmount;

        super._transfer(msg.sender, address(this), _sharesAmount);

        emit WithdrawRequest(msg.sender, _sharesAmount, currentRound);
    }

    function rolloverFromTrader() external override onlyTraderWallet {
        uint256 _pendingDepositAssets = pendingDepositAssets;
        uint256 _pendingWithdrawShares = pendingWithdrawShares;

        uint256 _currentRound = currentRound;

        (
            uint256 newAfterRoundBalance,
            uint256 underlyingPrice,
            uint256 _processedWithdrawAssets,
            address _underlyingTokenAddress,
            uint256 ONE_UNDERLYING_TOKEN
        ) = _getContractValuationPrivate(_currentRound, _pendingDepositAssets);

        _checkReservedAssets(
            _underlyingTokenAddress,
            _pendingDepositAssets,
            _processedWithdrawAssets
        );

        int256 roundProfitValuation;
        if (_currentRound != 0) {
            (newAfterRoundBalance, roundProfitValuation) = _calculateProfit(
                newAfterRoundBalance,
                underlyingPrice,
                ONE_UNDERLYING_TOKEN
            );
        }

        // express in underlying token
        roundProfitValuation = roundProfitValuation * int256(ONE_UNDERLYING_TOKEN) / int256(underlyingPrice);

        _underlyingPriceXRound[_currentRound] = underlyingPrice;

        // calculate `assetsPerShare`
        uint256 valuationPerShare;
        uint256 underlyingTokenPerShare;
        {
            uint256 _totalSupply = totalSupply();
            if (_totalSupply == 0) {
                valuationPerShare = 1e18;
            } else {
                valuationPerShare =
                    (newAfterRoundBalance * 1e18) /
                    _totalSupply;
            }

            // 1e18 for enhanced precision
            underlyingTokenPerShare =
                (valuationPerShare * 1e18 * 1e12) /
                underlyingPrice;
        }
        assetsPerShareXRound[_currentRound] = valuationPerShare;

        // calculate `sharesToMint`
        uint256 sharesToMint;
        if (_pendingDepositAssets > 0) {
            uint256 pendingDepositValuation = (_pendingDepositAssets *
                underlyingPrice) / ONE_UNDERLYING_TOKEN;

            sharesToMint = (pendingDepositValuation * 1e18) / valuationPerShare;
        }

        // @note Need to burn `_pendingWithdrawShares` and to mint `sharesToMint` shares
        if (sharesToMint > _pendingWithdrawShares) {
            super._mint(address(this), sharesToMint - _pendingWithdrawShares);
        } else if (sharesToMint < _pendingWithdrawShares) {
            super._burn(address(this), _pendingWithdrawShares - sharesToMint);
        }

        if (_pendingDepositAssets > 0) {
            delete pendingDepositAssets;

            if (_currentRound != 0) {
                // @note In the round zero they are already included in the `newAfterRoundBalance`
                newAfterRoundBalance +=
                    (_pendingDepositAssets * underlyingPrice) /
                    ONE_UNDERLYING_TOKEN;
            }
        }

        if (_pendingWithdrawShares > 0) {
            uint256 processedWithdrawAssetsValuation = (valuationPerShare *
                _pendingWithdrawShares) / 1e18;
            newAfterRoundBalance -= processedWithdrawAssetsValuation;

            uint256 newProcessedWithdrawAssets = (processedWithdrawAssetsValuation *
                    ONE_UNDERLYING_TOKEN) / underlyingPrice;
            _processedWithdrawAssets += newProcessedWithdrawAssets;
            processedWithdrawAssets = _processedWithdrawAssets;

            delete pendingWithdrawShares;
        }

        uint256 unusedFunds = _checkReservedAssets(
            _underlyingTokenAddress,
            0 /* _pendingDepositAssets */,
            _processedWithdrawAssets
        );

        afterRoundBalance = newAfterRoundBalance;
        currentRound = _currentRound + 1;

        currentSlippage = defaultSlippagePercent;
        isEmergencyOpen = false;

        emit UsersVaultRolloverExecuted(
            _currentRound,
            underlyingTokenPerShare,
            sharesToMint,
            _pendingWithdrawShares, // sharesToBurn
            roundProfitValuation,
            unusedFunds
        );
    }

    function executeOnProtocol(
        uint256 _protocolId,
        IAdapter.AdapterOperation memory _traderOperation,
        uint256 _ratio
    ) external override onlyTraderWallet {
        _checkZeroRound();

        if (_protocolId == 1) {
            _executeOnGmx(
                false,
                address(0),
                address(this),
                _ratio,
                _traderOperation
            );
        } else {
            _executeOnAdapter(
                _getAdapterAddress(_protocolId),
                false, // usersVault
                address(0), // no need
                address(this),
                _ratio,
                _traderOperation
            );
        }

        // @note Check that reserved tokens are not sold
        _checkReservedAssets(
            underlyingTokenAddress,
            pendingDepositAssets,
            processedWithdrawAssets
        );
    }

    function previewShares(
        address receiver
    ) external view override returns (uint256) {
        (UserData memory data, , ) = _updateUserDataInMemory(receiver);

        return data.unclaimedDepositShares;
    }

    function previewAssets(address receiver) external view returns (uint256) {
        (UserData memory data, , ) = _updateUserDataInMemory(receiver);

        return data.unclaimedWithdrawAssets;
    }

    function claim() external override {
        UserData memory data = _updateUserData(msg.sender);
        if(data.unclaimedDepositShares == 0 && data.unclaimedWithdrawAssets == 0){
            revert NoUnclaimedAmounts();
        } 
        if (data.unclaimedDepositShares > 0) {
            super._transfer(
                address(this),
                msg.sender,
                data.unclaimedDepositShares
            );

            delete _userData[msg.sender].unclaimedDepositShares;

            emit SharesClaimed(
                data.round,
                data.unclaimedDepositShares,
                msg.sender,
                msg.sender
            );
        }

        if (data.unclaimedWithdrawAssets > 0) {
            uint256 underlyingBalance = IERC20Upgradeable(underlyingTokenAddress)
                .balanceOf(address(this));

            uint256 transferAmount;
            if (underlyingBalance >= data.unclaimedWithdrawAssets) {
                transferAmount = data.unclaimedWithdrawAssets;
            } else {
                transferAmount = underlyingBalance;
            }

            _userData[msg.sender].unclaimedWithdrawAssets =
                data.unclaimedWithdrawAssets -
                transferAmount;

            IERC20Upgradeable(underlyingTokenAddress).safeTransfer(
                msg.sender,
                transferAmount
            );

            processedWithdrawAssets -= transferAmount;

            emit AssetsClaimed(
                data.round,
                transferAmount,
                msg.sender,
                msg.sender
            );
        }
    }

    //
    function getContractValuation() public view override returns (uint256) {
        (uint256 valuation, , , , ) = _getContractValuationPrivate(
            currentRound,
            pendingDepositAssets
        );

        return valuation;
    }

    function userData(
        address user
    ) external view override returns (UserData memory) {
        return _userData[user];
    }

    function getAllowedTradeTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return ITraderWallet(traderWalletAddress).getAllowedTradeTokens();
    }

    function getGmxShortCollaterals()
        external
        view
        override
        returns (address[] memory)
    {
        return ITraderWallet(traderWalletAddress).getGmxShortCollaterals();
    }

    function getGmxShortIndexTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return ITraderWallet(traderWalletAddress).getGmxShortIndexTokens();
    }

    function _checkReservedAssets(
        address _underlyingTokenAddress,
        uint256 _pendingDepositAssets,
        uint256 _processedWithdrawAssets
    ) private view returns (uint256) {
        uint256 reservedAssets = _pendingDepositAssets +
            _processedWithdrawAssets +
            kunjiFeesAssets;

        uint256 balance = IERC20Upgradeable(_underlyingTokenAddress).balanceOf(
            address(this)
        );

        if (balance < reservedAssets) {
            revert NotEnoughReservedAssets(balance, reservedAssets);
        }

        return balance - reservedAssets;
    }

    function _calculateProfit(
        uint256 newAfterRoundBalance,
        uint256 underlyingPrice,
        uint256 ONE_UNDERLYING_TOKEN
    )
        private
        returns (uint256 adjustedAfterRoundBalance, int256 roundProfitValuation)
    {
        roundProfitValuation =
            int256(newAfterRoundBalance) -
            int256(afterRoundBalance);
        uint256 feeRate = IContractsFactory(contractsFactoryAddress).feeRate();
        int256 kunjiFeesForRoundValuation = (roundProfitValuation *
            int256(feeRate)) / int256(BASE);

        int256 kunjiFeesForRoundAssets = (kunjiFeesForRoundValuation *
            int256(ONE_UNDERLYING_TOKEN)) / int256(underlyingPrice);
        uint256 _kunjiFeesAssets = kunjiFeesAssets;
        adjustedAfterRoundBalance = newAfterRoundBalance;
        if (int256(_kunjiFeesAssets) + kunjiFeesForRoundAssets < 0) {
            delete kunjiFeesAssets;

            // @note `newAfterRoundBalance` should be increased because reserved balance
            // of underlying tokens is decreased. It consists of pending deposits,
            // processed withdrawals, and kunji fees) =>
            // contract valuation is increased
            adjustedAfterRoundBalance +=
                (_kunjiFeesAssets * underlyingPrice) /
                ONE_UNDERLYING_TOKEN;
        } else {
            // @note always >= 0
            uint256 newKunjiFeesAssets = uint256(
                int256(_kunjiFeesAssets) + kunjiFeesForRoundAssets
            );

            if (kunjiFeesForRoundValuation > 0) {
                adjustedAfterRoundBalance -= uint256(kunjiFeesForRoundValuation);
            } else {
                // @note `newAfterRoundBalance` increases because `kunjiFeesAssets` decreases
                adjustedAfterRoundBalance += uint256(-1 * kunjiFeesForRoundValuation);
            }

            kunjiFeesAssets = newKunjiFeesAssets;
        }
    }

    function _getContractValuationPrivate(
        uint256 _currentRound,
        uint256 _pendingDepositAssets
    )
        private
        view
        returns (
            uint256 valuation,
            uint256 underlyingPrice,
            uint256 _processedWithdrawAssets,
            address _underlyingTokenAddress,
            uint256 ONE_UNDERLYING_TOKEN
        )
    {
        _currentRound = currentRound;
        _processedWithdrawAssets = processedWithdrawAssets;

        address dynamicValuationAddress = IContractsFactory(
            contractsFactoryAddress
        ).dynamicValuationAddress();
        _underlyingTokenAddress = underlyingTokenAddress;

        ONE_UNDERLYING_TOKEN = _ONE_UNDERLYING_TOKEN;
        underlyingPrice = IDynamicValuation(dynamicValuationAddress)
            .getOraclePrice(_underlyingTokenAddress, ONE_UNDERLYING_TOKEN);

        if (_currentRound == 0) {
            uint256 balance = IERC20Upgradeable(_underlyingTokenAddress).balanceOf(
                address(this)
            );

            valuation = (balance * underlyingPrice) / ONE_UNDERLYING_TOKEN;
        } else {
            uint256 totalVaultFundsValuation = IDynamicValuation(
                dynamicValuationAddress
            ).getDynamicValuation(address(this));

            uint256 pendingsFunds = _pendingDepositAssets +
                _processedWithdrawAssets +
                kunjiFeesAssets;
            uint256 pendingsFundsValuation = (pendingsFunds * underlyingPrice) /
                ONE_UNDERLYING_TOKEN;

            if (pendingsFundsValuation <= totalVaultFundsValuation) {
                valuation = totalVaultFundsValuation - pendingsFundsValuation;
            }
        }
    }

    function _updateUserDataInMemory(
        address user
    )
        private
        view
        returns (
            UserData memory data,
            bool updatedDepositData,
            bool updatedWithdrawData
        )
    {
        uint256 _currentRound = currentRound;

        data = _userData[user];

        if (
            data.round < _currentRound &&
            (data.pendingDepositAssets > 0 || data.pendingWithdrawShares > 0)
        ) {
            uint256 sharePrice = assetsPerShareXRound[data.round];

            uint256 underlyingPrice = _underlyingPriceXRound[data.round];

            if (data.pendingDepositAssets > 0) {
                uint256 pendingDepositValuation = (underlyingPrice *
                    data.pendingDepositAssets) / _ONE_UNDERLYING_TOKEN;

                data.unclaimedDepositShares +=
                    (pendingDepositValuation * 1e18) /
                    sharePrice;

                data.pendingDepositAssets = 0;

                updatedDepositData = true;
            }

            if (data.pendingWithdrawShares > 0) {
                uint256 processedWithdrawValuation = (data
                    .pendingWithdrawShares * sharePrice) / 1e18;

                data.unclaimedWithdrawAssets +=
                    (processedWithdrawValuation * _ONE_UNDERLYING_TOKEN) /
                    underlyingPrice;

                data.pendingWithdrawShares = 0;

                updatedWithdrawData = true;
            }
        }

        data.round = _currentRound;
    }

    function _updateUserData(
        address user
    ) private returns (UserData memory data) {
        bool updatedDepositData;
        bool updatedWithdrawData;
        (
            data,
            updatedDepositData,
            updatedWithdrawData
        ) = _updateUserDataInMemory(user);

        if (updatedDepositData) {
            delete _userData[user].pendingDepositAssets;
            _userData[user].unclaimedDepositShares = data
                .unclaimedDepositShares;
        }

        if (updatedWithdrawData) {
            delete _userData[user].pendingWithdrawShares;
            _userData[user].unclaimedWithdrawAssets = data
                .unclaimedWithdrawAssets;
        }

        // save to storage
        _userData[user].round = data.round;
    }

    /// @notice Functionality for emergency closing positions by any user.
    ///         Can be executed only after 15h since the last rollover()
    /// @dev Tries to close all positions
    function emergencyClose() external {
        address _traderWalletAddress = traderWalletAddress;
        if (
            ITraderWallet(_traderWalletAddress).lastRolloverTimestamp() +
                emergencyPeriod >
            block.timestamp &&
            !isEmergencyOpen
        ) revert TooEarly();
        bool isRequestFulfilled = _closeUniswapPositions(_traderWalletAddress);
        _closeGmxPositions(_traderWalletAddress);

        if (!isRequestFulfilled) {
            currentSlippage += slippageStepPercent;
            isEmergencyOpen = true;
        } else {
            currentSlippage = defaultSlippagePercent;
            isEmergencyOpen = false;
        }
    }

    /// @notice Closes uniswap positions by swapping them to underlying token
    /// @param _traderWalletAddress The bounded traderWallet address
    /// @return isRequestFulfilled The flag if 'requestedAmount' was fulfilled during closing
    function _closeUniswapPositions(
        address _traderWalletAddress
    ) internal returns (bool isRequestFulfilled) {
        // optimistically set true at start
        isRequestFulfilled = true;

        address[] memory tokens = ITraderWallet(_traderWalletAddress)
            .getAllowedTradeTokens();
        address _underlyingTokenAddress = underlyingTokenAddress;

        // first token in underlying, thus we pass it
        uint256 length = tokens.length;
        for (uint256 i = 1; i < length; ++i) {
            uint256 tokenBalance = IERC20MetadataUpgradeable(tokens[i]).balanceOf(
                _traderWalletAddress
            );
            if (tokenBalance > 0) {
                uint256 defaultSwapProtocol = 2; // uniswap
                IAdapter.AdapterOperation memory traderOperation;
                traderOperation.operationId = 1; // sell
                uint24 defaultPoolFee = 3000;
                bytes memory path = abi.encodePacked(
                    tokens[i],
                    defaultPoolFee,
                    _underlyingTokenAddress
                );

                uint256 amountOutMinimum = (_convertTokenAmountToUnderlyingAmount(
                        tokens[i],
                        tokenBalance
                    ) * (10000 - currentSlippage)) / 10000;

                traderOperation.data = abi.encode(
                    path,
                    tokenBalance,
                    amountOutMinimum
                );
                try
                    ITraderWallet(_traderWalletAddress).executeOnProtocol(
                        defaultSwapProtocol,
                        traderOperation,
                        true
                    )
                {
                    continue;
                } catch {
                    // try to swap 30% of initial amount
                    tokenBalance = (tokenBalance * 30) / 100;
                    amountOutMinimum =
                        (_convertTokenAmountToUnderlyingAmount(
                            tokens[i],
                            tokenBalance
                        ) * (10000 - currentSlippage)) /
                        10000;
                    traderOperation.data = abi.encode(
                        path,
                        tokenBalance,
                        amountOutMinimum
                    );
                    isRequestFulfilled = false;

                    try
                        ITraderWallet(_traderWalletAddress).executeOnProtocol(
                            defaultSwapProtocol,
                            traderOperation,
                            true
                        )
                    {} catch {
                        // increase default slippage for next tries
                        emit EmergencyCloseError(tokens[i], tokenBalance);
                    }
                }
            }
        }
        return (isRequestFulfilled);
    }

    /// @notice Closes GMX positions by creating market orders for closing
    /// @dev Positions will be closed in few next blocks due to GMX async behavior
    /// @param _traderWalletAddress The bounded traderWallet address
    /// @return isRequestFulfilled The flag if 'requestedAmount' was fulfilled during closing
    function _closeGmxPositions(
        address _traderWalletAddress
    ) internal returns (bool isRequestFulfilled) {
        // optimistically set true at start
        isRequestFulfilled = true;

        address lens = IContractsFactory(contractsFactoryAddress).lensAddress();
        ILens.ProcessedPosition[] memory positions = ILens(lens)
            .getAllPositionsProcessed(_traderWalletAddress);
        if (positions.length == 0) return true; // exit because there are no positions

        address _underlyingTokenAddress = underlyingTokenAddress;
        for (uint256 i; i < positions.length; ++i) {
            IAdapter.AdapterOperation memory traderOperation;
            traderOperation.operationId = 1; // decrease position
            uint256 collateralDelta; // collateralDelta=0 because it doesn't matter when closing FULL position
            uint256 minOut;
            address[] memory path;
            if (positions[i].collateralToken == _underlyingTokenAddress) {
                path = new address[](1);
                path[0] = _underlyingTokenAddress;
            } else {
                path = new address[](2);
                path[0] = positions[i].collateralToken;
                path[1] = _underlyingTokenAddress;
            }
            traderOperation.data = abi.encode(
                path,
                positions[i].indexToken,
                collateralDelta,
                positions[i].size,
                positions[i].isLong,
                minOut
            );
            try
                ITraderWallet(_traderWalletAddress).executeOnProtocol(
                    1, // GMX
                    traderOperation,
                    true // replicate
                )
            {} catch {
                isRequestFulfilled = false;
                emit EmergencyCloseError(
                    positions[i].indexToken,
                    positions[i].size
                );
                continue;
            }
        }
    }

    /// @notice Disable share transfer
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256
    ) internal virtual override {
        if (
            _from != address(0) && 
            _from != address(this) && 
            _to != address(0) && 
            _to != address(this)
        ) revert ShareTransferNotAllowed();
    }
}

