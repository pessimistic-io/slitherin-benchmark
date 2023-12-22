// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {IERC20Metadata, IERC20} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Base64} from "./Base64.sol";
import {IBinaryVaultFacet, IBinaryVault} from "./IBinaryVaultFacet.sol";
import {Strings} from "./StringUtils.sol";
import {IBinaryConfig} from "./IBinaryConfig.sol";
import {IBinaryVaultNFTFacet} from "./IBinaryVaultNFTFacet.sol";
import {IBinaryVaultPluginImpl} from "./IBinaryVaultPluginImpl.sol";
import {BinaryVaultDataType} from "./BinaryVaultDataType.sol";

library BinaryVaultFacetStorage {
    struct Layout {
        IBinaryConfig config;
        address underlyingTokenAddress;
        /// @notice Whitelisted markets, only whitelisted markets can take money out from the vault.
        mapping(address => BinaryVaultDataType.WhitelistedMarket) whitelistedMarkets;
        /// @notice share balances (token id => share balance)
        mapping(uint256 => uint256) shareBalances;
        /// @notice initial investment (tokenId => initial underlying token balance)
        mapping(uint256 => uint256) initialInvestments;
        /// @notice latest balance (token id => underlying token)
        /// @dev This should be updated when user deposits/withdraw or when take monthly management fee
        mapping(uint256 => uint256) recentSnapshots;
        // For risk management
        mapping(uint256 => BinaryVaultDataType.BetData) betData;
        // token id => request
        mapping(uint256 => BinaryVaultDataType.WithdrawalRequest) withdrawalRequests;
        mapping(address => bool) whitelistedUser;
        uint256 totalShareSupply;
        /// @notice TVL of vault. This should be updated when deposit(+), withdraw(-), trader lose (+), trader win (-), trading fees(+)
        uint256 totalDepositedAmount;
        /// @notice Watermark for risk management. This should be updated when deposit(+), withdraw(-), trading fees(+). If watermark < TVL, then set watermark = tvl
        uint256 watermark;
        // @notice Current pending withdrawal share amount. Plus when new withdrawal request, minus when cancel or execute withdraw.
        uint256 pendingWithdrawalTokenAmount;
        uint256 pendingWithdrawalShareAmount;
        uint256 withdrawalDelayTime;
        /// @dev The interval during which the maximum bet amount changes
        uint256 lastTimestampForExposure;
        uint256 currentHourlyExposureAmount;
        bool pauseNewDeposit;
        bool useWhitelist;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("balancecapital.ryze.storage.BinaryVaultFacet");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

interface IVaultDiamond {
    function owner() external view returns (address);
}

contract BinaryVaultFacet is
    ReentrancyGuard,
    IBinaryVaultFacet,
    IBinaryVaultPluginImpl
{
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using Strings for string;

    uint256 private constant MAX_DELAY = 1 weeks;

    event LiquidityAdded(
        address indexed user,
        uint256 oldTokenId,
        uint256 newTokenId,
        uint256 amount,
        uint256 newShareAmount
    );
    event PositionMerged(
        address indexed user,
        uint256[] tokenIds,
        uint256 newTokenId
    );
    event LiquidityRemoved(
        address indexed user,
        uint256 tokenId,
        uint256 newTokenId,
        uint256 amount,
        uint256 shareAmount,
        uint256 newShares
    );
    event WithdrawalRequested(
        address indexed user,
        uint256 shareAmount,
        uint256 tokenId
    );
    event WithdrawalRequestCanceled(
        address indexed user,
        uint256 tokenId,
        uint256 shareAmount,
        uint256 underlyingTokenAmount
    );
    event VaultChangedFromMarket(
        uint256 prevTvl,
        uint256 totalDepositedAmount,
        uint256 watermark
    );
    event ManagementFeeWithdrawed();
    event ConfigChanged(address indexed config);
    event WhitelistMarketChanged(address indexed market, bool enabled);

    modifier onlyMarket() {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        require(s.whitelistedMarkets[msg.sender].whitelisted, "ONLY_MARKET");
        _;
    }

    modifier onlyOwner() {
        require(
            IVaultDiamond(address(this)).owner() == msg.sender,
            "Ownable: caller is not the owner"
        );
        _;
    }

    function initialize(address underlyingToken_, address config_)
        external
        onlyOwner
    {
        require(underlyingToken_ != address(0), "ZERO_ADDRESS");
        require(config_ != address(0), "ZERO_ADDRESS");
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        s.underlyingTokenAddress = underlyingToken_;
        s.config = IBinaryConfig(config_);
        s.withdrawalDelayTime = 24 hours;
    }

    /// @notice Whitelist market on the vault
    /// @dev Only owner can call this function
    /// @param market Market contract address
    /// @param whitelist Whitelist or Blacklist
    /// @param exposureBips Exposure percent based 10_000. So 100% is 10_000
    function setWhitelistMarket(
        address market,
        bool whitelist,
        uint256 exposureBips
    ) external virtual onlyOwner {
        require(market != address(0), "ZERO_ADDRESS");

        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        require(exposureBips <= s.config.FEE_BASE(), "INVALID_BIPS");

        s.whitelistedMarkets[market].whitelisted = whitelist;
        s.whitelistedMarkets[market].exposureBips = exposureBips;

        emit WhitelistMarketChanged(market, whitelist);
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
                newShares
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
                newShares
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
    function mergePositions(uint256[] memory tokenIds)
        external
        virtual
        nonReentrant
    {
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

        emit PositionMerged(msg.sender, tokenIds, _newTokenId);
    }

    /// @notice Request withdrawal (This request will be delayed for withdrawalDelayTime)
    /// @param shareAmount share amount to be burnt
    /// @param tokenId This is available when fromPosition is true
    function requestWithdrawal(uint256 shareAmount, uint256 tokenId)
        external
        virtual
    {
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

        emit WithdrawalRequested(msg.sender, shareAmount, tokenId);

        _updateExposureAmount();
    }

    /// @notice Execute withdrawal request if it passed enough time.
    /// @param tokenId withdrawal request id to be executed.
    function executeWithdrawalRequest(uint256 tokenId)
        external
        virtual
        nonReentrant
    {
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
            ,
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
        if (shareAmount < shareBalance) {
            // Mint new one for dust
            newTokenId = IBinaryVaultNFTFacet(address(this)).nextTokenId();
            s.shareBalances[newTokenId] = shareBalance - shareAmount;
            s.initialInvestments[newTokenId] =
                ((shareBalance - shareAmount) * initialInvest) /
                shareBalance;

            s.recentSnapshots[newTokenId] =
                s.recentSnapshots[tokenId] -
                (shareAmount * s.recentSnapshots[tokenId]) /
                shareBalance;
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
            shareBalance - shareAmount
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

    /// @notice Claim winning rewards from the vault
    /// In this case, we charge fee from win traders.
    /// @dev Only markets can call this function
    /// @param user Address of winner
    /// @param amount Amount of rewards to claim
    /// @param isRefund whether its refund
    /// @return claim amount
    function claimBettingRewards(
        address user,
        uint256 amount,
        bool isRefund
    ) external virtual onlyMarket returns (uint256) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 claimAmount = isRefund
            ? amount
            : ((2 * amount * (s.config.FEE_BASE() - s.config.tradingFee())) /
                s.config.FEE_BASE());
        IERC20(s.underlyingTokenAddress).safeTransfer(user, claimAmount);

        return claimAmount;
    }

    /// @notice Get shares of user.
    /// @param user address
    /// @return shares underlyingTokenAmount netValue fee their values
    function getSharesOfUser(address user)
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
    function getSharesOfToken(uint256 tokenId)
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

    /// @dev set config
    function setConfig(address _config) external virtual onlyOwner {
        require(_config != address(0), "ZERO_ADDRESS");
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        s.config = IBinaryConfig(_config);

        emit ConfigChanged(_config);
    }

    function enableUseWhitelist(bool value) external onlyOwner {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();
        require(s.useWhitelist != value, "ALREADY_SET");
        s.useWhitelist = value;
    }

    function enablePauseDeposit(bool value) external onlyOwner {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();
        require(s.pauseNewDeposit != value, "ALREADY_SET");
        s.pauseNewDeposit = value;
    }

    function setWhitelistUser(address user, bool value) external onlyOwner {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();
        require(s.whitelistedUser[user] != value, "ALREADY_SET");
        s.whitelistedUser[user] = value;
    }

    /// @dev This function is used to update total deposited amount from user betting
    /// @param wonAmount amount won from user perspective (lost from vault perspective)
    /// @param loseAmount amount lost from user perspective (won from vault perspective)
    function onRoundExecuted(uint256 wonAmount, uint256 loseAmount)
        external
        virtual
        override
        onlyMarket
    {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 tradingFeeBips = s.config.tradingFee();
        uint256 fee1 = (wonAmount * tradingFeeBips) / s.config.FEE_BASE();
        uint256 fee2 = (loseAmount * tradingFeeBips) / s.config.FEE_BASE();
        uint256 remainingAmountForWon = fee1;

        uint256 tradingFee = fee1 + fee2;

        uint256 prevTvl = s.totalDepositedAmount;

        if (loseAmount - fee2 > wonAmount - remainingAmountForWon) {
            // winner will claim: amount * 2 * 95%, and we will charge trading fee amount * 5%, so amount * 5% will remain in vault. this is same as fee1 amount.
            // for lose transaction, 95% will remain in vault, and we will charge trading fee amount * 5% 
            // deposit amount: loseAmount - fee2, payout amount: wonAmount - remainingAmountForWon
            s.totalDepositedAmount += (loseAmount - fee2) - (wonAmount - remainingAmountForWon);
        } else {
            uint256 escapeAmount = wonAmount + fee2 - remainingAmountForWon - loseAmount;
            s.totalDepositedAmount = s.totalDepositedAmount >= escapeAmount
                ? s.totalDepositedAmount - escapeAmount
                : 0;
        }

        // Update watermark
        if (s.totalDepositedAmount > s.watermark) {
            s.watermark = s.totalDepositedAmount;
        }

        if (tradingFee > 0) {
            IERC20(s.underlyingTokenAddress).safeTransfer(
                s.config.treasuryForReferrals(),
                tradingFee
            );
        }

        emit VaultChangedFromMarket(
            prevTvl,
            s.totalDepositedAmount,
            s.watermark
        );
    }

    /// @notice Set withdrawal delay time
    /// @param _time time in seconds
    function setWithdrawalDelayTime(uint256 _time) external virtual onlyOwner {
        require(_time <= MAX_DELAY, "INVALID_TIME");
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        s.withdrawalDelayTime = _time;
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

    function getShareBipsExpression(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 percent = (s.shareBalances[tokenId] * 10_000) /
            s.totalShareSupply;
        string memory percentString = percent.getFloatExpression();
        return string(abi.encodePacked(percentString, " %"));
    }

    function getInitialInvestExpression(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 _value = s.initialInvestments[tokenId];
        string memory floatExpression = ((_value * 10**2) /
            10**IERC20Metadata(s.underlyingTokenAddress).decimals())
            .getFloatExpression();
        return
            string(
                abi.encodePacked(
                    floatExpression,
                    " ",
                    IERC20Metadata(s.underlyingTokenAddress).symbol()
                )
            );
    }

    function getCurrentValueExpression(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        (, , uint256 netValue, ) = getSharesOfToken(tokenId);
        string memory floatExpression = ((netValue * 10**2) /
            10**IERC20Metadata(s.underlyingTokenAddress).decimals())
            .getFloatExpression();
        return
            string(
                abi.encodePacked(
                    floatExpression,
                    " ",
                    IERC20Metadata(s.underlyingTokenAddress).symbol()
                )
            );
    }

    function getWithdrawalExpression(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        BinaryVaultDataType.WithdrawalRequest memory withdrawalRequest = s
            .withdrawalRequests[tokenId];
        if (withdrawalRequest.timestamp == 0) {
            return "Active";
        } else if (
            withdrawalRequest.timestamp + s.withdrawalDelayTime <=
            block.timestamp
        ) {
            return "Executable";
        } else {
            return "Pending";
        }
    }

    function getImagePlainText(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        string memory template = s.config.binaryVaultImageTemplate();

        string memory result = template.replaceString(
            "<!--TOKEN_ID-->",
            tokenId.toString()
        );
        result = result.replaceString(
            "<!--SHARE_BIPS-->",
            getShareBipsExpression(tokenId)
        );
        result = result.replaceString(
            "<!--VAULT_NAME-->",
            IERC20Metadata(s.underlyingTokenAddress).symbol()
        );
        result = result.replaceString(
            "<!--VAULT_STATUS-->",
            getWithdrawalExpression(tokenId)
        );
        result = result.replaceString(
            "<!--DEPOSIT_AMOUNT-->",
            getInitialInvestExpression(tokenId)
        );
        result = result.replaceString(
            "<!--VAULT_LOGO_IMAGE-->",
            s.config.tokenLogo(s.underlyingTokenAddress)
        );
        result = result.replaceString(
            "<!--VAULT_VALUE-->",
            getCurrentValueExpression(tokenId)
        );

        string memory baseURL = "data:image/svg+xml;base64,";
        string memory svgBase64Encoded = Base64.encode(
            bytes(string(abi.encodePacked(result)))
        );

        return string(abi.encodePacked(baseURL, svgBase64Encoded));
    }

    /// @notice constructs manifest metadata in plaintext for base64 encoding
    /// @param _tokenId token id
    /// @return _manifest manifest for base64 encoding
    function getManifestPlainText(uint256 _tokenId)
        internal
        view
        virtual
        returns (string memory _manifest)
    {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        string memory image = getImagePlainText(_tokenId);

        _manifest = string(
            abi.encodePacked(
                '{"name": ',
                '"',
                IBinaryVaultNFTFacet(address(this)).name(),
                '", "description": "',
                s.config.vaultDescription(),
                '", "image": "',
                image,
                '"}'
            )
        );
    }

    function generateTokenURI(uint256 tokenId)
        external
        view
        returns (string memory)
    {
        string memory output = getManifestPlainText(tokenId);
        string memory json = Base64.encode(bytes(output));

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function cancelExpiredWithdrawalRequest(uint256 tokenId)
        external
        onlyOwner
    {
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

    /// @notice Transfer underlying token from user to vault. Update vault state for risk management
    /// @param amount bet amount
    /// @param from originating user
    /// @param endTime round close time
    /// @param position bull if 0, bear if 1 for binary options
    function onPlaceBet(
        uint256 amount,
        address from,
        uint256 endTime,
        uint8 position
    ) external virtual onlyMarket {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        IERC20(s.underlyingTokenAddress).safeTransferFrom(
            from,
            address(this),
            amount
        );
        BinaryVaultDataType.BetData storage data = s.betData[endTime];

        if (position == 0) {
            data.bullAmount += amount;
        } else {
            data.bearAmount += amount;
        }
    }

    function getExposureAmountAt(uint256 endTime)
        public
        view
        virtual
        returns (uint256 exposureAmount, uint8 direction)
    {
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

    /// @notice This is function for withdraw management fee - Ryze Fee
    /// We run this function at certain day, for example 25th in every month.
    /// @dev We set from and to parameter so that we can avoid falling in gas limitation issue
    /// @param from tokenId where we will start to get management fee
    /// @param to tokenId where we will end to get management fee
    function withdrawManagementFee(uint256 from, uint256 to)
        external
        virtual
        onlyOwner
    {
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

            uint256 sharePrice = (s.totalDepositedAmount * 10**18) /
                s.totalShareSupply;
            if (sharePrice > 10**18) {
                s.totalShareSupply = s.totalDepositedAmount;
                for (uint256 tokenId = from; tokenId <= to; tokenId++) {
                    s.shareBalances[tokenId] =
                        (s.shareBalances[tokenId] * sharePrice) /
                        10**18;
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

    // getter functions
    function config() external view returns (address) {
        return address(BinaryVaultFacetStorage.layout().config);
    }

    function underlyingTokenAddress() external view returns (address) {
        return BinaryVaultFacetStorage.layout().underlyingTokenAddress;
    }

    function whitelistMarkets(address market)
        external
        view
        returns (bool, uint256)
    {
        return (
            BinaryVaultFacetStorage
                .layout()
                .whitelistedMarkets[market]
                .whitelisted,
            BinaryVaultFacetStorage
                .layout()
                .whitelistedMarkets[market]
                .exposureBips
        );
    }

    function shareBalances(uint256 tokenId) external view returns (uint256) {
        return BinaryVaultFacetStorage.layout().shareBalances[tokenId];
    }

    function initialInvestments(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        return BinaryVaultFacetStorage.layout().initialInvestments[tokenId];
    }

    function recentSnapshots(uint256 tokenId) external view returns (uint256) {
        return BinaryVaultFacetStorage.layout().recentSnapshots[tokenId];
    }

    function withdrawalRequests(uint256 tokenId)
        external
        view
        returns (BinaryVaultDataType.WithdrawalRequest memory)
    {
        return BinaryVaultFacetStorage.layout().withdrawalRequests[tokenId];
    }

    function totalShareSupply() external view returns (uint256) {
        return BinaryVaultFacetStorage.layout().totalShareSupply;
    }

    function totalDepositedAmount() external view returns (uint256) {
        return BinaryVaultFacetStorage.layout().totalDepositedAmount;
    }

    function watermark() external view returns (uint256) {
        return BinaryVaultFacetStorage.layout().watermark;
    }

    function pendingWithdrawalShareAmount() external view returns (uint256) {
        return BinaryVaultFacetStorage.layout().pendingWithdrawalShareAmount;
    }

    function pendingWithdrawalTokenAmount() external view returns (uint256) {
        return BinaryVaultFacetStorage.layout().pendingWithdrawalTokenAmount;
    }

    function withdrawalDelayTime() external view returns (uint256) {
        return BinaryVaultFacetStorage.layout().withdrawalDelayTime;
    }

    function isDepositPaused() external view returns (bool) {
        return BinaryVaultFacetStorage.layout().pauseNewDeposit;
    }

    function isWhitelistedUser(address user) external view returns (bool) {
        return BinaryVaultFacetStorage.layout().whitelistedUser[user];
    }

    function isUseWhitelist() external view returns (bool) {
        return BinaryVaultFacetStorage.layout().useWhitelist;
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
        s = new bytes4[](42);
        s[0] = IBinaryVault.claimBettingRewards.selector;
        s[1] = IBinaryVault.onRoundExecuted.selector;
        s[2] = IBinaryVault.getMaxHourlyExposure.selector;
        s[3] = IBinaryVault.isFutureBettingAvailable.selector;
        s[4] = IBinaryVault.onPlaceBet.selector;
        s[5] = IBinaryVault.getExposureAmountAt.selector;
        s[6] = IBinaryVaultFacet.setWhitelistMarket.selector;
        s[7] = IBinaryVaultFacet.addLiquidity.selector;
        s[8] = IBinaryVaultFacet.mergePositions.selector;
        s[9] = IBinaryVaultFacet.requestWithdrawal.selector;
        s[10] = IBinaryVaultFacet.executeWithdrawalRequest.selector;
        s[11] = IBinaryVaultFacet.cancelWithdrawalRequest.selector;
        s[12] = IBinaryVaultFacet.getSharesOfUser.selector;
        s[13] = IBinaryVaultFacet.getSharesOfToken.selector;
        s[14] = IBinaryVaultFacet.setConfig.selector;
        s[15] = IBinaryVaultFacet.setWithdrawalDelayTime.selector;
        s[16] = IBinaryVaultFacet.cancelExpiredWithdrawalRequest.selector;
        s[17] = IBinaryVaultFacet.getPendingRiskFromBet.selector;
        s[18] = IBinaryVaultFacet.withdrawManagementFee.selector;
        s[19] = IBinaryVaultFacet.getManagementFee.selector;
        s[20] = IBinaryVaultFacet.generateTokenURI.selector;

        s[21] = IBinaryVaultFacet.config.selector;
        s[22] = IBinaryVaultFacet.underlyingTokenAddress.selector;
        s[23] = IBinaryVault.whitelistMarkets.selector;
        s[24] = IBinaryVaultFacet.shareBalances.selector;
        s[25] = IBinaryVaultFacet.initialInvestments.selector;
        s[26] = IBinaryVaultFacet.recentSnapshots.selector;
        s[27] = IBinaryVaultFacet.withdrawalRequests.selector;
        s[28] = IBinaryVaultFacet.totalShareSupply.selector;
        s[29] = IBinaryVaultFacet.totalDepositedAmount.selector;
        s[30] = IBinaryVaultFacet.watermark.selector;
        s[31] = IBinaryVaultFacet.pendingWithdrawalShareAmount.selector;
        s[32] = IBinaryVaultFacet.pendingWithdrawalTokenAmount.selector;
        s[33] = IBinaryVaultFacet.withdrawalDelayTime.selector;

        s[34] = IBinaryVaultFacet.isDepositPaused.selector;
        s[35] = IBinaryVaultFacet.isWhitelistedUser.selector;
        s[36] = IBinaryVaultFacet.isUseWhitelist.selector;
        s[37] = IBinaryVaultFacet.enableUseWhitelist.selector;
        s[38] = IBinaryVaultFacet.enablePauseDeposit.selector;
        s[39] = IBinaryVaultFacet.setWhitelistUser.selector;
        s[40] = IBinaryVault.updateExposureAmount.selector;
        s[41] = IBinaryVault.getCurrentHourlyExposureAmount.selector;
    }

    function pluginMetadata()
        external
        pure
        returns (bytes4[] memory selectors, bytes4 interfaceId)
    {
        selectors = pluginSelectors();
        interfaceId = type(IBinaryVaultFacet).interfaceId;
    }
}

