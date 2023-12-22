// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Base64Upgradeable.sol";
import "./IERC20Metadata.sol";
import "./ERC721AUpgradeable.sol";

import "./IBinaryVault.sol";
import "./IBinaryConfig.sol";
import "./StringUtils.sol";

/// @notice Singleton pattern for Ryze Platform, can run multiple markets on same underlying asset
/// @author https://balance.capital
contract BinaryVault is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721AUpgradeable,
    IBinaryVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using Strings for uint256;
    using Strings for string;

    struct WithdrawalRequest {
        uint256 tokenId; // nft id
        uint256 shareAmount; // share amount
        uint256 underlyingTokenAmount; // underlying token amount
        uint256 timestamp; // request block time
        uint256 minExpectAmount; // Minimum underlying amount which user will receive
        uint256 fee;
    }

    struct BetData {
        uint256 bullAmount;
        uint256 bearAmount;
    }

    IBinaryConfig public config;
    address public underlyingTokenAddress;
    /// @notice Whitelisted markets, only whitelisted markets can take money out from the vault.
    mapping(address => bool) public whitelistedMarkets;

    /// @notice share balances (token id => share balance)
    mapping(uint256 => uint256) public shareBalances;
    /// @notice initial investment (tokenId => initial underlying token balance)
    mapping(uint256 => uint256) public initialInvestments;

    /// @notice latest balance (token id => underlying token)
    /// @dev This should be updated when user deposits/withdraw or when take monthly management fee
    mapping(uint256 => uint256) public recentSnapshots;

    // For risk management
    mapping(uint256 => BetData) public betData;

    // token id => request
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    uint256 public totalShareSupply;

    /// @notice TVL of vault. This should be updated when deposit(+), withdraw(-), trader lose (+), trader win (-), trading fees(+)
    uint256 public totalDepositedAmount;
    /// @notice Watermark for risk management. This should be updated when deposit(+), withdraw(-), trading fees(+). If watermark < TVL, then set watermark = tvl
    uint256 public watermark;

    // @notice Current pending withdrawal share amount. Plus when new withdrawal request, minus when cancel or execute withdraw.
    uint256 public pendingWithdrawalTokenAmount;
    uint256 public pendingWithdrawalShareAmount;

    uint256 public withdrawalDelayTime;
    uint256 public constant MAX_DELAY = 1 weeks;

    event ConfigChanged(address indexed config);
    event WhitelistMarketChanged(address indexed market, bool enabled);

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

    modifier onlyMarket() {
        require(whitelistedMarkets[msg.sender], "ONLY_MARKET");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        string memory name,
        string memory symbol,
        address underlyingToken_,
        address config_
    ) public initializerERC721A initializer {
        require(underlyingToken_ != address(0), "ZERO_ADDRESS");
        require(config_ != address(0), "ZERO_ADDRESS");

        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC721A_init(name, symbol);

        underlyingTokenAddress = underlyingToken_;

        config = IBinaryConfig(config_);

        withdrawalDelayTime = 24 hours;
    }

    /// @notice Whitelist market on the vault
    /// @dev Only owner can call this function
    /// @param market Market contract address
    /// @param whitelist Whitelist or Blacklist
    function setWhitelistMarket(address market, bool whitelist)
        public
        virtual
        onlyOwner
    {
        require(market != address(0), "ZERO_ADDRESS");
        whitelistedMarkets[market] = whitelist;

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

        if (!isNew) {
            require(ownerOf(tokenId) == msg.sender, "NOT_OWNER");

            WithdrawalRequest memory withdrawalRequest = withdrawalRequests[
                tokenId
            ];
            require(withdrawalRequest.timestamp == 0, "TOKEN_IN_ACTION");
        }

        // Transfer underlying token from user to the vault
        IERC20Upgradeable(underlyingTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Calculate new share amount base on current share price
        if (totalShareSupply > 0) {
            newShares = (amount * totalShareSupply) / totalDepositedAmount;
        } else {
            newShares = amount;
        }

        totalShareSupply += newShares;
        totalDepositedAmount += amount;
        watermark += amount;

        if (isNew) {
            tokenId = _nextTokenId();
            // Mint new position with that amount
            shareBalances[tokenId] = newShares;
            initialInvestments[tokenId] = amount;
            recentSnapshots[tokenId] = amount;
            _mint(msg.sender, 1);

            emit LiquidityAdded(
                msg.sender,
                tokenId,
                tokenId,
                amount,
                newShares
            );
        } else {
            // Current share amount of this token ID;
            uint256 currentShares = shareBalances[tokenId];
            uint256 currentInitialInvestments = initialInvestments[tokenId];
            uint256 currentSnapshot = recentSnapshots[tokenId];
            // Burn existing one
            __burn(tokenId);
            // Mint New position.
            uint256 newTokenId = _nextTokenId();

            shareBalances[newTokenId] = currentShares + newShares;
            initialInvestments[newTokenId] = currentInitialInvestments + amount;
            recentSnapshots[newTokenId] = currentSnapshot + amount;

            _mint(msg.sender, 1);

            emit LiquidityAdded(
                msg.sender,
                tokenId,
                newTokenId,
                amount,
                newShares
            );
        }
    }

    function __burn(uint256 tokenId) internal virtual {
        _burn(tokenId);

        delete shareBalances[tokenId];
        delete initialInvestments[tokenId];
        delete recentSnapshots[tokenId];
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

        for (uint256 i; i < tokenIds.length; i = i + 1) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenId) == msg.sender, "NOT_OWNER");

            shareAmounts += shareBalances[tokenId];
            initialInvests += initialInvestments[tokenId];
            snapshots += recentSnapshots[tokenId];

            __burn(tokenId);
        }

        uint256 _newTokenId = _nextTokenId();
        shareBalances[_newTokenId] = shareAmounts;
        initialInvestments[_newTokenId] = initialInvests;
        recentSnapshots[_newTokenId] = snapshots;
        _mint(msg.sender, 1);

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
        require(ownerOf(tokenId) == msg.sender, "NOT_OWNER");
        WithdrawalRequest memory r = withdrawalRequests[tokenId];

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

        pendingRisk = (pendingRisk * shareAmount) / totalShareSupply;

        uint256 minExpectAmount = underlyingTokenAmount > pendingRisk
            ? underlyingTokenAmount - pendingRisk
            : 0;
        WithdrawalRequest memory _request = WithdrawalRequest(
            tokenId,
            shareAmount,
            underlyingTokenAmount,
            block.timestamp,
            minExpectAmount,
            feeAmount
        );

        withdrawalRequests[tokenId] = _request;

        pendingWithdrawalTokenAmount += underlyingTokenAmount;
        pendingWithdrawalShareAmount += shareAmount;

        emit WithdrawalRequested(msg.sender, shareAmount, tokenId);
    }

    /// @notice Execute withdrawal request if it passed enough time.
    /// @param tokenId withdrawal request id to be executed.
    function executeWithdrawalRequest(uint256 tokenId)
        external
        virtual
        nonReentrant
    {
        address user = msg.sender;

        require(user == ownerOf(tokenId), "NOT_REQUEST_OWNER");

        WithdrawalRequest memory _request = withdrawalRequests[tokenId];
        // Check if time is passed enough
        require(
            block.timestamp >= _request.timestamp + withdrawalDelayTime,
            "TOO_EARLY"
        );

        uint256 shareAmount = _request.shareAmount;
        require(shareAmount > 0, "ZERO_AMOUNT");

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
            IERC20Upgradeable(underlyingTokenAddress).safeTransfer(
                config.treasury(),
                fee
            );
        }

        uint256 redeemAmount = (netValue * shareAmount) / shareBalance;
        // Send money to user
        IERC20Upgradeable(underlyingTokenAddress).safeTransfer(
            user,
            redeemAmount
        );

        // Mint dust
        uint256 initialInvest = initialInvestments[tokenId];

        uint256 newTokenId;
        if (shareAmount < shareBalance) {
            // Mint new one for dust
            newTokenId = _nextTokenId();
            shareBalances[newTokenId] = shareBalance - shareAmount;
            initialInvestments[newTokenId] =
                ((shareBalance - shareAmount) * initialInvest) /
                shareBalance;

            recentSnapshots[newTokenId] =
                recentSnapshots[tokenId] -
                (shareAmount * recentSnapshots[tokenId]) /
                shareBalance;
            _mint(user, 1);
        }

        // deduct
        totalDepositedAmount -= (redeemAmount + fee);
        watermark -= (redeemAmount + fee);
        totalShareSupply -= shareAmount;

        pendingWithdrawalTokenAmount -= _request.underlyingTokenAmount;
        pendingWithdrawalShareAmount -= _request.shareAmount;

        delete withdrawalRequests[tokenId];
        __burn(tokenId);

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
        require(msg.sender == ownerOf(tokenId), "NOT_REQUEST_OWNER");
        _cancelWithdrawalRequest(tokenId);
    }

    function _cancelWithdrawalRequest(uint256 tokenId) internal {
        require(_exists(tokenId), "INVALID_TOKEN_ID");

        WithdrawalRequest memory request = withdrawalRequests[tokenId];
        require(request.timestamp > 0, "NOT_EXIST_REQUEST");

        pendingWithdrawalTokenAmount -= request.underlyingTokenAmount;
        pendingWithdrawalShareAmount -= request.shareAmount;

        emit WithdrawalRequestCanceled(
            msg.sender,
            tokenId,
            request.shareAmount,
            request.underlyingTokenAmount
        );

        delete withdrawalRequests[tokenId];
    }

    /// @notice Check if future betting is available based on current pending withdrawal request amount
    /// @return future betting is available
    function isFutureBettingAvailable() external view returns (bool) {
        if (
            pendingWithdrawalTokenAmount >=
            (totalDepositedAmount *
                config.maxWithdrawalBipsForFutureBettingAvailable()) /
                config.FEE_BASE()
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
        uint256 claimAmount = isRefund
            ? amount
            : (amount +
                (amount * (config.FEE_BASE() - config.tradingFee())) /
                config.FEE_BASE());
        IERC20Upgradeable(underlyingTokenAddress).safeTransfer(
            user,
            claimAmount
        );

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
        uint256[] memory tokenIds = tokensOfOwner(user);

        if (tokenIds.length == 0) {
            return (0, 0, 0, 0);
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
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
        if (!_exists(tokenId)) {
            return (0, 0, 0, 0);
        }

        shares = shareBalances[tokenId];
        fee = 0;

        uint256 lastSnapshot = recentSnapshots[tokenId];

        uint256 totalShareSupply_ = totalShareSupply;
        uint256 totalDepositedAmount_ = totalDepositedAmount;

        tokenValue = (shares * totalDepositedAmount_) / totalShareSupply_;

        netValue = tokenValue;

        if (tokenValue > lastSnapshot) {
            // This token got profit. In this case, we should deduct fee (30%)
            fee =
                ((tokenValue - lastSnapshot) * config.treasuryBips()) /
                config.FEE_BASE();
            netValue = tokenValue - fee;
        }
    }

    /// @return Get next token id
    function nextTokenId() public view virtual returns (uint256) {
        return _nextTokenId();
    }

    /// @dev set config
    function setConfig(IBinaryConfig _config) external virtual onlyOwner {
        require(address(_config) != address(0), "ZERO_ADDRESS");
        config = _config;

        emit ConfigChanged(address(_config));
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
        wonAmount -= (wonAmount * config.tradingFee()) / config.FEE_BASE();
        uint256 prevTvl = totalDepositedAmount;

        if (loseAmount > wonAmount) {
            totalDepositedAmount += (loseAmount - wonAmount);
        } else if (loseAmount < wonAmount) {
            uint256 escapeAmount = wonAmount - loseAmount;
            totalDepositedAmount = totalDepositedAmount >= escapeAmount
                ? totalDepositedAmount - escapeAmount
                : 0;
        }

        // Update watermark
        if (totalDepositedAmount > watermark) {
            watermark = totalDepositedAmount;
        }

        emit VaultChangedFromMarket(prevTvl, totalDepositedAmount, watermark);
    }

    /// @notice Set withdrawal delay time
    /// @param _time time in seconds
    function setWithdrawalDelayTime(uint256 _time) external virtual onlyOwner {
        require(_time <= MAX_DELAY, "INVALID_TIME");
        withdrawalDelayTime = _time;
    }

    /// @return Get vault risk
    function getVaultRiskBips() internal view virtual returns (uint256) {
        if (watermark < totalDepositedAmount) {
            return 0;
        }

        return
            ((watermark - totalDepositedAmount) * config.FEE_BASE()) /
            totalDepositedAmount;
    }

    /// @return Get max hourly vault exposure based on current risk. if current risk is high, hourly vault exposure should be decreased.
    function getMaxHourlyExposure() external view virtual returns (uint256) {
        uint256 tvl = totalDepositedAmount - pendingWithdrawalTokenAmount;

        if (tvl == 0) {
            return 0;
        }

        uint256 currentRiskBips = getVaultRiskBips();
        uint256 _maxHourlyExposureBips = config.maxHourlyExposure();
        uint256 _maxVaultRiskBips = config.maxVaultRiskBips();

        if (currentRiskBips >= _maxVaultRiskBips) {
            // Risk is too high. Stop accepting bet
            return 0;
        }

        uint256 exposureBips = (_maxHourlyExposureBips *
            (_maxVaultRiskBips - currentRiskBips)) / _maxVaultRiskBips;

        return (exposureBips * tvl) / config.FEE_BASE();
    }

    /// @notice Sync TVL, balance, watermark
    function sync() external virtual onlyOwner {
        uint256 _tokenBalance = IERC20Upgradeable(underlyingTokenAddress)
            .balanceOf(address(this));

        totalDepositedAmount = _tokenBalance;
        watermark = totalDepositedAmount;
    }

    /// @notice Generate string expression with floating number - 123 => 1.23%. Base number is 10_000
    /// @param percent percent with 2 decimals
    /// @return string representation
    function getFloatExpression(uint256 percent)
        internal
        pure
        virtual
        returns (string memory)
    {
        string memory percentString = (percent / 100).toString();
        uint256 decimal = percent % 100;
        if (decimal > 0) {
            percentString = string(
                abi.encodePacked(
                    percentString,
                    ".",
                    (decimal / 10).toString(),
                    (decimal % 10).toString()
                )
            );
        }
        return percentString;
    }

    function getShareBipsExpression(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        uint256 percent = (shareBalances[tokenId] * 10_000) / totalShareSupply;
        string memory percentString = getFloatExpression(percent);
        return string(abi.encodePacked(percentString, " %"));
    }

    function getInitialInvestExpression(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        uint256 _value = initialInvestments[tokenId];
        string memory floatExpression = getFloatExpression(
            (_value * 10**2) /
                10**IERC20Metadata(underlyingTokenAddress).decimals()
        );
        return
            string(
                abi.encodePacked(
                    floatExpression,
                    " ",
                    IERC20Metadata(underlyingTokenAddress).symbol()
                )
            );
    }

    function getCurrentValueExpression(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        (, , uint256 netValue, ) = getSharesOfToken(tokenId);
        string memory floatExpression = getFloatExpression(
            (netValue * 10**2) /
                10**IERC20Metadata(underlyingTokenAddress).decimals()
        );
        return
            string(
                abi.encodePacked(
                    floatExpression,
                    " ",
                    IERC20Metadata(underlyingTokenAddress).symbol()
                )
            );
    }

    function getWithdrawalExpression(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        WithdrawalRequest memory withdrawalRequest = withdrawalRequests[
            tokenId
        ];
        if (withdrawalRequest.timestamp == 0) {
            return "Active";
        } else if (
            withdrawalRequest.timestamp + withdrawalDelayTime <= block.timestamp
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
        string memory template = config.binaryVaultImageTemplate();

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
            IERC20Metadata(underlyingTokenAddress).symbol()
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
            config.tokenLogo(underlyingTokenAddress)
        );
        result = result.replaceString(
            "<!--VAULT_VALUE-->",
            getCurrentValueExpression(tokenId)
        );

        string memory baseURL = "data:image/svg+xml;base64,";
        string memory svgBase64Encoded = Base64Upgradeable.encode(
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
        string memory image = getImagePlainText(_tokenId);

        _manifest = string(
            abi.encodePacked(
                '{"name": ',
                '"',
                name(),
                '", "description": "',
                config.vaultDescription(),
                '", "image": "',
                image,
                '"}'
            )
        );
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        string memory output = getManifestPlainText(tokenId);
        string memory json = Base64Upgradeable.encode(bytes(output));

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function withdrawToken(address _token) external virtual onlyOwner {
        require(_token != underlyingTokenAddress, "INVALID_TOKEN");

        IERC20Upgradeable(_token).safeTransfer(
            msg.sender,
            IERC20Upgradeable(_token).balanceOf(address(this))
        );
    }

    function cancelExpiredWithdrawalRequest(uint256 tokenId)
        external
        onlyOwner
    {
        WithdrawalRequest memory request = withdrawalRequests[tokenId];
        require(
            block.timestamp > request.timestamp + withdrawalDelayTime * 2,
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
        IERC20Upgradeable(underlyingTokenAddress).safeTransferFrom(
            from,
            address(this),
            amount
        );
        BetData storage data = betData[endTime];

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
        BetData memory data = betData[endTime];

        if (data.bullAmount > data.bearAmount) {
            exposureAmount = data.bullAmount - data.bearAmount;
            direction = 0;
        } else {
            exposureAmount = data.bearAmount - data.bullAmount;
            direction = 1;
        }
    }

    function getPendingRiskFromBet() public view returns (uint256 riskAmount) {
        uint256 nextMinuteTimestamp = block.timestamp -
            (block.timestamp % 60) +
            60;
        uint256 futureBettingTimeUpTo = config.futureBettingTimeUpTo();

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

        for (uint256 tokenId = from; tokenId <= to; tokenId++) {
            (, , uint256 netValue, uint256 fee) = getSharesOfToken(tokenId);
            if (fee > 0) {
                feeAmount += fee;
                uint256 feeShare = (fee * totalShareSupply) /
                    totalDepositedAmount;
                if (shareBalances[tokenId] >= feeShare) {
                    shareBalances[tokenId] = shareBalances[tokenId] - feeShare;
                }
                // We will set recent snapshot so that we will prevent to charge duplicated fee.
                recentSnapshots[tokenId] = netValue;
            }
        }
        if (feeAmount > 0) {
            uint256 feeShare = (feeAmount * totalShareSupply) /
                totalDepositedAmount;

            IERC20Upgradeable(underlyingTokenAddress).safeTransfer(
                config.treasury(),
                feeAmount
            );
            totalDepositedAmount -= feeAmount;
            watermark -= feeAmount;
            totalShareSupply -= feeShare;

            uint256 sharePrice = (totalDepositedAmount * 10**18) /
                totalShareSupply;
            if (sharePrice > 10**18) {
                totalShareSupply = totalDepositedAmount;
                for (uint256 tokenId = from; tokenId <= to; tokenId++) {
                    shareBalances[tokenId] =
                        (shareBalances[tokenId] * sharePrice) /
                        10**18;
                }
            }
        }
    }

    function getManagementFee() public view returns (uint256 feeAmount) {
        uint256 to = _nextTokenId();
        for (uint256 tokenId = 0; tokenId < to; tokenId++) {
            (, , , uint256 fee) = getSharesOfToken(tokenId);
            feeAmount += fee;
        }
    }

    /**
     * @dev Returns an array of token IDs owned by `owner`.
     *
     * This function scans the ownership mapping and is O(`totalSupply`) in complexity.
     * It is meant to be called off-chain.
     *
     * See {ERC721AQueryable-tokensOfOwnerIn} for splitting the scan into
     * multiple smaller scans if the collection is large enough to cause
     * an out-of-gas error (10K collections should be fine).
     */
    function tokensOfOwner(address owner)
        public
        view
        returns (uint256[] memory)
    {
        unchecked {
            uint256 tokenIdsIdx;
            address currOwnershipAddr;
            uint256 tokenIdsLength = balanceOf(owner);
            uint256[] memory tokenIds = new uint256[](tokenIdsLength);
            TokenOwnership memory ownership;
            for (
                uint256 i = _startTokenId();
                tokenIdsIdx != tokenIdsLength;
                ++i
            ) {
                ownership = _ownershipAt(i);
                if (ownership.burned) {
                    continue;
                }
                if (ownership.addr != address(0)) {
                    currOwnershipAddr = ownership.addr;
                }
                if (currOwnershipAddr == owner) {
                    tokenIds[tokenIdsIdx++] = i;
                }
            }
            return tokenIds;
        }
    }
}

