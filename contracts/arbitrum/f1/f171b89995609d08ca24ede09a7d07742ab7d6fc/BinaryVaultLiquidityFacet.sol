// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IBinaryVaultPluginImpl} from "./IBinaryVaultPluginImpl.sol";
import {IBinaryVaultNFTFacet} from "./IBinaryVaultNFTFacet.sol";
import {IBinaryVaultLiquidityFacet} from "./IBinaryVaultLiquidityFacet.sol";
import {BinaryVaultDataType} from "./BinaryVaultDataType.sol";
import {BinaryVaultFacetStorage, IVaultDiamond} from "./BinaryVaultBaseFacet.sol";

contract BinaryVaultLiquidityFacet is
    ReentrancyGuard,
    IBinaryVaultLiquidityFacet,
    IBinaryVaultPluginImpl
{
    using SafeERC20 for IERC20;

    event LiquidityAdded(
        address indexed user,
        uint256 oldTokenId,
        uint256 newTokenId,
        uint256 amount,
        uint256 newShareAmount,
        uint256 newSnapshot,
        uint256 newTokenValue
    );
    event PositionMerged(
        address indexed user,
        uint256[] tokenIds,
        uint256 newTokenId,
        uint256 newSnapshot,
        uint256 newTokenValue
    );
    event LiquidityRemoved(
        address indexed user,
        uint256 tokenId,
        uint256 newTokenId,
        uint256 amount,
        uint256 shareAmount,
        uint256 newShares,
        uint256 newSnapshot,
        uint256 newTokenValue,
        uint256 fee
    );
    event WithdrawalRequested(
        address indexed user,
        uint256 shareAmount,
        uint256 tokenId,
        uint256 fee
    );
    event WithdrawalRequestCanceled(
        address indexed user,
        uint256 tokenId,
        uint256 shareAmount,
        uint256 underlyingTokenAmount
    );
    event ManagementFeeWithdrawed();

    modifier onlyFromDiamond() {
        require(msg.sender == address(this), "INVALID_CALLER");
        _;
    }
    modifier onlyOwner() {
        require(
            IVaultDiamond(address(this)).owner() == msg.sender,
            "Ownable: caller is not the owner"
        );
        _;
    }

    /// @notice Add liquidity. Burn existing token, mint new one.
    /// @param tokenId if isNew = false, nft id to be added liquidity..
    /// @param amount Underlying token amount
    /// @param isNew adding new liquidity or adding liquidity to existing position.
    function addLiquidity(
        uint256 tokenId,
        uint256 amount,
        bool isNew
    ) external virtual nonReentrant returns (uint256 newShares) {
        require(amount > 0, "ZERO_AMOUNT");
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        require(!s.pauseNewDeposit, "DEPOSIT_PAUSED");
        if (s.useWhitelist)
            require(s.whitelistedUser[msg.sender], "NOT_WHITELISTED");

        if (!isNew) {
            require(
                IBinaryVaultNFTFacet(address(this)).ownerOf(tokenId) ==
                    msg.sender,
                "NOT_OWNER"
            );

            BinaryVaultDataType.WithdrawalRequest memory withdrawalRequest = s
                .withdrawalRequests[tokenId];
            require(withdrawalRequest.timestamp == 0, "TOKEN_IN_ACTION");
        }

        // Transfer underlying token from user to the vault
        IERC20(s.underlyingTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Calculate new share amount base on current share price
        if (s.totalShareSupply > 0) {
            newShares = (amount * s.totalShareSupply) / s.totalDepositedAmount;
        } else {
            newShares = amount;
        }

        s.totalShareSupply += newShares;
        s.totalDepositedAmount += amount;
        s.watermark += amount;

        if (isNew) {
            tokenId = IBinaryVaultNFTFacet(address(this)).nextTokenId();
            // Mint new position with that amount
            s.shareBalances[tokenId] = newShares;
            s.initialInvestments[tokenId] = amount;
            s.recentSnapshots[tokenId] = amount;
            IBinaryVaultNFTFacet(address(this)).mint(msg.sender);

            emit LiquidityAdded(
                msg.sender,
                tokenId,
                tokenId,
                amount,
                newShares,
                amount,
                amount
            );
        } else {
            // Current share amount of this token ID;
            uint256 currentShares = s.shareBalances[tokenId];
            uint256 currentInitialInvestments = s.initialInvestments[tokenId];
            uint256 currentSnapshot = s.recentSnapshots[tokenId];
            // Burn existing one
            __burn(tokenId);
            // Mint New position.
            uint256 newTokenId = IBinaryVaultNFTFacet(address(this))
                .nextTokenId();

            s.shareBalances[newTokenId] = currentShares + newShares;
            s.initialInvestments[newTokenId] =
                currentInitialInvestments +
                amount;
            s.recentSnapshots[newTokenId] = currentSnapshot + amount;

            IBinaryVaultNFTFacet(address(this)).mint(msg.sender);

            emit LiquidityAdded(
                msg.sender,
                tokenId,
                newTokenId,
                amount,
                newShares,
                s.recentSnapshots[newTokenId],
                (s.shareBalances[newTokenId] * s.totalDepositedAmount) /
                    s.totalShareSupply
            );
        }

        _updateExposureAmount();
    }

    function __burn(uint256 tokenId) internal virtual {
        IBinaryVaultNFTFacet(address(this)).burn(tokenId);
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        delete s.shareBalances[tokenId];
        delete s.initialInvestments[tokenId];
        delete s.recentSnapshots[tokenId];
        if (s.withdrawalRequests[tokenId].timestamp > 0) {
            delete s.withdrawalRequests[tokenId];
        }
    }

    /// @notice Merge tokens into one, Burn existing ones and mint new one
    /// @param tokenIds Token ids which will be merged
    function mergePositions(
        uint256[] memory tokenIds
    ) external virtual nonReentrant {
        uint256 shareAmounts = 0;
        uint256 initialInvests = 0;
        uint256 snapshots = 0;
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 withdrawalShareAmount;
        uint256 withdrawalTokenAmount;
        for (uint256 i; i < tokenIds.length; i = i + 1) {
            uint256 tokenId = tokenIds[i];
            require(
                IBinaryVaultNFTFacet(address(this)).ownerOf(tokenId) ==
                    msg.sender,
                "NOT_OWNER"
            );

            shareAmounts += s.shareBalances[tokenId];
            initialInvests += s.initialInvestments[tokenId];
            snapshots += s.recentSnapshots[tokenId];

            BinaryVaultDataType.WithdrawalRequest memory request = s
                .withdrawalRequests[tokenId];
            if (request.timestamp > 0) {
                withdrawalTokenAmount += request.underlyingTokenAmount;
                withdrawalShareAmount += request.shareAmount;
            }

            __burn(tokenId);
        }

        uint256 _newTokenId = IBinaryVaultNFTFacet(address(this)).nextTokenId();
        s.shareBalances[_newTokenId] = shareAmounts;
        s.initialInvestments[_newTokenId] = initialInvests;
        s.recentSnapshots[_newTokenId] = snapshots;

        if (withdrawalTokenAmount > 0) {
            s.pendingWithdrawalShareAmount -= withdrawalShareAmount;
            s.pendingWithdrawalTokenAmount -= withdrawalTokenAmount;
        }

        IBinaryVaultNFTFacet(address(this)).mint(msg.sender);

        emit PositionMerged(
            msg.sender,
            tokenIds,
            _newTokenId,
            s.recentSnapshots[_newTokenId],
            (s.shareBalances[_newTokenId] * s.totalDepositedAmount) /
                s.totalShareSupply
        );
    }

    /// @notice Request withdrawal (This request will be delayed for withdrawalDelayTime)
    /// @param shareAmount share amount to be burnt
    /// @param tokenId This is available when fromPosition is true
    function requestWithdrawal(
        uint256 shareAmount,
        uint256 tokenId
    ) external virtual {
        require(shareAmount > 0, "TOO_SMALL_AMOUNT");
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        require(
            IBinaryVaultNFTFacet(address(this)).ownerOf(tokenId) == msg.sender,
            "NOT_OWNER"
        );
        BinaryVaultDataType.WithdrawalRequest memory r = s.withdrawalRequests[
            tokenId
        ];

        require(r.timestamp == 0, "ALREADY_REQUESTED");

        // We decrease tvl once user requests withdrawal. so this liquidity won't be affected by user's betting.
        (
            uint256 shareBalance,
            uint256 tokenValue,
            ,
            uint256 fee
        ) = getSharesOfToken(tokenId);

        require(shareBalance >= shareAmount, "INSUFFICIENT_AMOUNT");

        uint256 underlyingTokenAmount = (tokenValue * shareAmount) /
            shareBalance;
        uint256 feeAmount = (fee * shareAmount) / shareBalance;

        // Get total pending risk
        uint256 pendingRisk = getPendingRiskFromBet();

        pendingRisk = (pendingRisk * shareAmount) / s.totalShareSupply;

        uint256 minExpectAmount = underlyingTokenAmount > pendingRisk
            ? underlyingTokenAmount - pendingRisk
            : 0;
        BinaryVaultDataType.WithdrawalRequest
            memory _request = BinaryVaultDataType.WithdrawalRequest(
                tokenId,
                shareAmount,
                underlyingTokenAmount,
                block.timestamp,
                minExpectAmount,
                feeAmount
            );

        s.withdrawalRequests[tokenId] = _request;

        s.pendingWithdrawalTokenAmount += underlyingTokenAmount;
        s.pendingWithdrawalShareAmount += shareAmount;

        emit WithdrawalRequested(
            msg.sender,
            shareAmount,
            tokenId,
            _request.fee
        );

        _updateExposureAmount();
    }

    /// @notice Execute withdrawal request if it passed enough time.
    /// @param tokenId withdrawal request id to be executed.
    function executeWithdrawalRequest(
        uint256 tokenId
    ) external virtual nonReentrant {
        address user = msg.sender;

        require(
            user == IBinaryVaultNFTFacet(address(this)).ownerOf(tokenId),
            "NOT_REQUEST_OWNER"
        );
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        BinaryVaultDataType.WithdrawalRequest memory _request = s
            .withdrawalRequests[tokenId];
        // Check if time is passed enough
        require(
            block.timestamp >= _request.timestamp + s.withdrawalDelayTime,
            "TOO_EARLY"
        );

        uint256 shareAmount = _request.shareAmount;

        (
            uint256 shareBalance,
            uint256 tokenValue,
            uint256 netValue,
            uint256 fee
        ) = getSharesOfToken(tokenId);

        if (shareAmount > shareBalance) {
            shareAmount = shareBalance;
        }

        fee = (fee * shareAmount) / shareBalance;
        if (fee > 0) {
            // Send fee to treasury
            IERC20(s.underlyingTokenAddress).safeTransfer(
                s.config.treasury(),
                fee
            );
        }

        uint256 redeemAmount = (netValue * shareAmount) / shareBalance;
        // Send money to user
        IERC20(s.underlyingTokenAddress).safeTransfer(user, redeemAmount);

        // Mint dust
        uint256 initialInvest = s.initialInvestments[tokenId];

        uint256 newTokenId;
        uint256 newSnapshot;
        if (shareAmount < shareBalance) {
            // Mint new one for dust
            newTokenId = IBinaryVaultNFTFacet(address(this)).nextTokenId();
            s.shareBalances[newTokenId] = shareBalance - shareAmount;
            s.initialInvestments[newTokenId] =
                ((shareBalance - shareAmount) * initialInvest) /
                shareBalance;

            newSnapshot =
                s.recentSnapshots[tokenId] -
                (shareAmount * s.recentSnapshots[tokenId]) /
                shareBalance;
            s.recentSnapshots[newTokenId] = newSnapshot;
            IBinaryVaultNFTFacet(address(this)).mint(user);
        }

        // deduct
        s.totalDepositedAmount -= (redeemAmount + fee);
        s.watermark -= (redeemAmount + fee);
        s.totalShareSupply -= shareAmount;

        s.pendingWithdrawalTokenAmount -= _request.underlyingTokenAmount;
        s.pendingWithdrawalShareAmount -= _request.shareAmount;

        delete s.withdrawalRequests[tokenId];
        __burn(tokenId);

        _updateExposureAmount();

        emit LiquidityRemoved(
            user,
            tokenId,
            newTokenId,
            redeemAmount,
            shareAmount,
            shareBalance - shareAmount,
            newSnapshot,
            tokenValue > redeemAmount ? tokenValue - redeemAmount : 0,
            fee
        );
    }

    /// @notice Cancel withdrawal request
    /// @param tokenId nft id
    function cancelWithdrawalRequest(uint256 tokenId) external virtual {
        require(
            msg.sender == IBinaryVaultNFTFacet(address(this)).ownerOf(tokenId),
            "NOT_REQUEST_OWNER"
        );
        _cancelWithdrawalRequest(tokenId);
    }

    function _cancelWithdrawalRequest(uint256 tokenId) internal {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        BinaryVaultDataType.WithdrawalRequest memory request = s
            .withdrawalRequests[tokenId];
        require(request.timestamp > 0, "NOT_EXIST_REQUEST");

        s.pendingWithdrawalTokenAmount -= request.underlyingTokenAmount;
        s.pendingWithdrawalShareAmount -= request.shareAmount;

        emit WithdrawalRequestCanceled(
            msg.sender,
            tokenId,
            request.shareAmount,
            request.underlyingTokenAmount
        );

        delete s.withdrawalRequests[tokenId];
        _updateExposureAmount();
    }

    function cancelExpiredWithdrawalRequest(
        uint256 tokenId
    ) external onlyOwner {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        BinaryVaultDataType.WithdrawalRequest memory request = s
            .withdrawalRequests[tokenId];
        require(
            block.timestamp > request.timestamp + s.withdrawalDelayTime * 2,
            "INVALID"
        );
        _cancelWithdrawalRequest(tokenId);
    }

    /// @notice Get shares of user.
    /// @param user address
    /// @return shares underlyingTokenAmount netValue fee their values
    function getSharesOfUser(
        address user
    )
        public
        view
        virtual
        returns (
            uint256 shares,
            uint256 underlyingTokenAmount,
            uint256 netValue,
            uint256 fee
        )
    {
        uint256[] memory tokenIds = IBinaryVaultNFTFacet(address(this))
            .tokensOfOwner(user);

        if (tokenIds.length == 0) {
            return (0, 0, 0, 0);
        }

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            (
                uint256 shareAmount,
                uint256 uTokenAmount,
                uint256 net,
                uint256 _fee
            ) = getSharesOfToken(tokenIds[i]);
            shares += shareAmount;
            underlyingTokenAmount += uTokenAmount;
            netValue += net;
            fee += _fee;
        }
    }

    /// @notice Get shares and underlying token amount of token
    /// @return shares tokenValue netValue fee - their values
    function getSharesOfToken(
        uint256 tokenId
    )
        public
        view
        virtual
        returns (
            uint256 shares,
            uint256 tokenValue,
            uint256 netValue,
            uint256 fee
        )
    {
        if (!IBinaryVaultNFTFacet(address(this)).exists(tokenId)) {
            return (0, 0, 0, 0);
        }
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        shares = s.shareBalances[tokenId];
        fee = 0;

        uint256 lastSnapshot = s.recentSnapshots[tokenId];

        uint256 totalShareSupply_ = s.totalShareSupply;
        uint256 totalDepositedAmount_ = s.totalDepositedAmount;

        tokenValue = (shares * totalDepositedAmount_) / totalShareSupply_;

        netValue = tokenValue;

        if (tokenValue > lastSnapshot) {
            // This token got profit. In this case, we should deduct fee (30%)
            fee =
                ((tokenValue - lastSnapshot) * s.config.treasuryBips()) /
                s.config.FEE_BASE();
            netValue = tokenValue - fee;
        }
    }

    /// @notice This is function for withdraw management fee - Ryze Fee
    /// We run this function at certain day, for example 25th in every month.
    /// @dev We set from and to parameter so that we can avoid falling in gas limitation issue
    /// @param from tokenId where we will start to get management fee
    /// @param to tokenId where we will end to get management fee
    function withdrawManagementFee(
        uint256 from,
        uint256 to
    ) external virtual onlyOwner {
        _withdrawManagementFee(from, to);
        emit ManagementFeeWithdrawed();
    }

    function _withdrawManagementFee(uint256 from, uint256 to) internal virtual {
        uint256 feeAmount;
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        for (uint256 tokenId = from; tokenId <= to; tokenId++) {
            (, , uint256 netValue, uint256 fee) = getSharesOfToken(tokenId);
            if (fee > 0) {
                feeAmount += fee;
                uint256 feeShare = (fee * s.totalShareSupply) /
                    s.totalDepositedAmount;
                if (s.shareBalances[tokenId] >= feeShare) {
                    s.shareBalances[tokenId] =
                        s.shareBalances[tokenId] -
                        feeShare;
                }
                // We will set recent snapshot so that we will prevent to charge duplicated fee.
                s.recentSnapshots[tokenId] = netValue;
            }
        }
        if (feeAmount > 0) {
            uint256 feeShare = (feeAmount * s.totalShareSupply) /
                s.totalDepositedAmount;

            IERC20(s.underlyingTokenAddress).safeTransfer(
                s.config.treasury(),
                feeAmount
            );
            s.totalDepositedAmount -= feeAmount;
            s.watermark -= feeAmount;
            s.totalShareSupply -= feeShare;

            uint256 sharePrice = (s.totalDepositedAmount * 10 ** 18) /
                s.totalShareSupply;
            if (sharePrice > 10 ** 18) {
                s.totalShareSupply = s.totalDepositedAmount;
                for (uint256 tokenId = from; tokenId <= to; tokenId++) {
                    s.shareBalances[tokenId] =
                        (s.shareBalances[tokenId] * sharePrice) /
                        10 ** 18;
                }
            }
        }
    }

    function getManagementFee() external view returns (uint256 feeAmount) {
        uint256 to = IBinaryVaultNFTFacet(address(this)).nextTokenId();
        for (uint256 tokenId = 0; tokenId < to; tokenId++) {
            (, , , uint256 fee) = getSharesOfToken(tokenId);
            feeAmount += fee;
        }
    }

    function _updateExposureAmount() internal {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        s.currentHourlyExposureAmount = getMaxHourlyExposure();
        s.lastTimestampForExposure = block.timestamp;
    }

    function updateExposureAmount() external {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        if (
            block.timestamp >=
            s.lastTimestampForExposure + s.config.intervalForExposureUpdate()
        ) {
            _updateExposureAmount();
        }
    }

    /// @notice Check if future betting is available based on current pending withdrawal request amount
    /// @return future betting is available
    function isFutureBettingAvailable() external view returns (bool) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        if (
            s.pendingWithdrawalTokenAmount >=
            (s.totalDepositedAmount *
                s.config.maxWithdrawalBipsForFutureBettingAvailable()) /
                s.config.FEE_BASE()
        ) {
            return false;
        } else {
            return true;
        }
    }

    /// @return Get vault risk
    function getVaultRiskBips() internal view virtual returns (uint256) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        if (s.watermark < s.totalDepositedAmount) {
            return 0;
        }

        return
            ((s.watermark - s.totalDepositedAmount) * s.config.FEE_BASE()) /
            s.totalDepositedAmount;
    }

    /// @return Get max hourly vault exposure based on current risk. if current risk is high, hourly vault exposure should be decreased.
    function getMaxHourlyExposure() public view virtual returns (uint256) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 tvl = s.totalDepositedAmount - s.pendingWithdrawalTokenAmount;

        if (tvl == 0) {
            return 0;
        }

        uint256 currentRiskBips = getVaultRiskBips();
        uint256 _maxHourlyExposureBips = s.config.maxHourlyExposure();
        uint256 _maxVaultRiskBips = s.config.maxVaultRiskBips();

        if (currentRiskBips >= _maxVaultRiskBips) {
            // Risk is too high. Stop accepting bet
            return 0;
        }

        uint256 exposureBips = (_maxHourlyExposureBips *
            (_maxVaultRiskBips - currentRiskBips)) / _maxVaultRiskBips;

        return (exposureBips * tvl) / s.config.FEE_BASE();
    }

    function getExposureAmountAt(
        uint256 endTime
    ) public view virtual returns (uint256 exposureAmount, uint8 direction) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        BinaryVaultDataType.BetData memory data = s.betData[endTime];

        if (data.bullAmount > data.bearAmount) {
            exposureAmount = data.bullAmount - data.bearAmount;
            direction = 0;
        } else {
            exposureAmount = data.bearAmount - data.bullAmount;
            direction = 1;
        }
    }

    function getPendingRiskFromBet() public view returns (uint256 riskAmount) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 nextMinuteTimestamp = block.timestamp -
            (block.timestamp % 60) +
            60;
        uint256 futureBettingTimeUpTo = s.config.futureBettingTimeUpTo();

        for (
            uint256 i = nextMinuteTimestamp;
            i <= nextMinuteTimestamp + futureBettingTimeUpTo;
            i += 60
        ) {
            (uint256 exposureAmount, ) = getExposureAmountAt(i);
            riskAmount += exposureAmount;
        }
    }

    function getCurrentHourlyExposureAmount() external view returns (uint256) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        if (
            block.timestamp >=
            s.lastTimestampForExposure + s.config.intervalForExposureUpdate()
        ) {
            return getMaxHourlyExposure();
        } else {
            return s.currentHourlyExposureAmount;
        }
    }

    function pluginSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](16);
        s[0] = BinaryVaultLiquidityFacet.addLiquidity.selector;
        s[1] = BinaryVaultLiquidityFacet.mergePositions.selector;
        s[2] = BinaryVaultLiquidityFacet.requestWithdrawal.selector;
        s[3] = BinaryVaultLiquidityFacet.executeWithdrawalRequest.selector;
        s[4] = BinaryVaultLiquidityFacet.cancelWithdrawalRequest.selector;
        s[5] = IBinaryVaultLiquidityFacet.getSharesOfUser.selector;
        s[6] = IBinaryVaultLiquidityFacet.getSharesOfToken.selector;
        s[7] = BinaryVaultLiquidityFacet.withdrawManagementFee.selector;
        s[8] = BinaryVaultLiquidityFacet.cancelExpiredWithdrawalRequest.selector;
        s[9] = BinaryVaultLiquidityFacet.getManagementFee.selector;
        s[10] = BinaryVaultLiquidityFacet.updateExposureAmount.selector;
        s[11] = IBinaryVaultLiquidityFacet.isFutureBettingAvailable.selector;
        s[12] = IBinaryVaultLiquidityFacet.getMaxHourlyExposure.selector;
        s[13] = IBinaryVaultLiquidityFacet.getExposureAmountAt.selector;
        s[14] = IBinaryVaultLiquidityFacet.getPendingRiskFromBet.selector;
        s[15] = IBinaryVaultLiquidityFacet.getCurrentHourlyExposureAmount.selector;
    }

    function pluginMetadata()
        external
        pure
        returns (bytes4[] memory selectors, bytes4 interfaceId)
    {
        selectors = pluginSelectors();
        interfaceId = type(IBinaryVaultLiquidityFacet).interfaceId;
    }
}

