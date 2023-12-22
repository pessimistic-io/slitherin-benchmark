// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./Ownable2StepUpgradeable.sol";
import {Unauthorized, IllegalState, IllegalArgument} from "./Errors.sol";
import "./IYieldStrategyManager.sol";
import "./ITokenAdapter.sol";

import "./Sets.sol";
import "./Checker.sol";
import "./TokenUtils.sol";
import "./Math.sol";

import "./Mutex.sol";

contract YieldStrategyManager is
    IYieldStrategyManager,
    Mutex,
    Ownable2StepUpgradeable
{
    using Limiters for Limiters.LinearGrowthLimiter;
    using Sets for Sets.AddressSet;

    /// @notice The number of basis points there are to represent exactly 100%.
    uint256 public constant BPS = 10000;

    /// @notice The scalar used for conversion of integral numbers to fixed point numbers. Fixed point numbers in this
    ///         implementation have 18 decimals of resolution, meaning that 1 is represented as 1e18, 0.5 is
    ///         represented as 5e17, and 2 is represented as 2e18.
    uint256 public constant FIXED_POINT_SCALAR = 1e18;

    /// @dev Base token parameters mapped by token address.
    mapping(address => BaseTokenParams) private _baseTokens;

    /// @dev yield token parameters mapped by token address.
    mapping(address => YieldTokenParams) private _yieldTokens;

    /// @dev A linear growth function that limits the amount of debt-token borrowed.
    Limiters.LinearGrowthLimiter private _borrowingLimiter;

    // @dev The repay limiters for each base token.
    mapping(address => Limiters.LinearGrowthLimiter) private _repayLimiters;

    // @dev The repayWithCollateral limiters for each base token.
    mapping(address => Limiters.LinearGrowthLimiter)
        private _repayWithCollateralLimiters;

    /// @dev An iterable set of the base tokens that are supported by the system.
    Sets.AddressSet private _supportedBaseTokens;

    /// @dev An iterable set of the yield tokens that are supported by the system.
    Sets.AddressSet private _supportedYieldTokens;

    /// @dev The address of SavvyPositionManager.
    address public savvyPositionManager;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    modifier onlySavvyPositionManager() {
        require(msg.sender == savvyPositionManager, "Unauthorized");
        _;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function setSavvyPositionManager(
        address savvyPositionManager_
    ) external onlyOwner {
        savvyPositionManager = savvyPositionManager_;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getBaseTokensPerShare(
        address yieldToken
    ) external view returns (uint256) {
        (, uint256 baseTokenAmount) = convertSharesToBaseTokens(
            yieldToken,
            FIXED_POINT_SCALAR
        );
        return baseTokenAmount;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getYieldTokensPerShare(
        address yieldToken
    ) external view returns (uint256) {
        return convertSharesToYieldTokens(yieldToken, FIXED_POINT_SCALAR);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getSupportedBaseTokens() external view returns (address[] memory) {
        return _supportedBaseTokens.values;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getSupportedYieldTokens()
        external
        view
        returns (address[] memory)
    {
        return _supportedYieldTokens.values;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function isSupportedBaseToken(
        address baseToken
    ) external view returns (bool) {
        return _supportedBaseTokens.contains(baseToken);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function isSupportedYieldToken(
        address yieldToken
    ) external view returns (bool) {
        return _supportedYieldTokens.contains(yieldToken);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getBaseTokenParameters(
        address baseToken
    ) external view returns (BaseTokenParams memory) {
        return _baseTokens[baseToken];
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getYieldTokenParameters(
        address yieldToken
    ) external view returns (YieldTokenParams memory) {
        return _yieldTokens[yieldToken];
    }

    function borrowingLimiter()
        external
        view
        returns (Limiters.LinearGrowthLimiter memory)
    {
        return _borrowingLimiter;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getBorrowLimitInfo()
        external
        view
        returns (uint256 currentLimit, uint256 rate, uint256 maximum)
    {
        return (
            _borrowingLimiter.get(),
            _borrowingLimiter.rate,
            _borrowingLimiter.maximum
        );
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getRepayLimitInfo(
        address baseToken
    )
        external
        view
        returns (uint256 currentLimit, uint256 rate, uint256 maximum)
    {
        Limiters.LinearGrowthLimiter storage limiter = _repayLimiters[
            baseToken
        ];
        return (limiter.get(), limiter.rate, limiter.maximum);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getRepayWithCollateralLimitInfo(
        address baseToken
    )
        external
        view
        returns (uint256 currentLimit, uint256 rate, uint256 maximum)
    {
        Limiters.LinearGrowthLimiter
            storage limiter = _repayWithCollateralLimiters[baseToken];
        return (limiter.get(), limiter.rate, limiter.maximum);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function decreaseBorrowingLimiter(
        uint256 amount
    ) external onlySavvyPositionManager {
        _borrowingLimiter.decrease(amount);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function increaseBorrowingLimiter(
        uint256 amount
    ) external onlySavvyPositionManager {
        _borrowingLimiter.increase(amount);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function decreaseRepayWithCollateralLimiter(
        address baseToken,
        uint256 amount
    ) external onlySavvyPositionManager {
        _repayWithCollateralLimiters[baseToken].decrease(amount);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function decreaseRepayWithBaseTokenLimiter(
        address baseToken,
        uint256 amount
    ) external onlySavvyPositionManager {
        _repayLimiters[baseToken].decrease(amount);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function addBaseToken(
        address debtToken,
        address baseToken,
        ISavvyAdminActions.BaseTokenConfig calldata config
    ) external onlySavvyPositionManager {
        Checker.checkState(
            !_supportedBaseTokens.contains(baseToken),
            "same base token already exists"
        );

        uint8 tokenDecimals = TokenUtils.expectDecimals(baseToken);
        uint8 debtTokenDecimals = TokenUtils.expectDecimals(debtToken);

        Checker.checkArgument(
            tokenDecimals < 19 && tokenDecimals < debtTokenDecimals + 1,
            "invalid token decimals"
        );

        _baseTokens[baseToken] = BaseTokenParams({
            decimals: tokenDecimals,
            conversionFactor: 10 ** (debtTokenDecimals - tokenDecimals),
            enabled: false
        });

        _repayLimiters[baseToken] = Limiters.createLinearGrowthLimiter(
            config.repayLimitMaximum,
            config.repayLimitBlocks,
            config.repayLimitMinimum
        );

        _repayWithCollateralLimiters[baseToken] = Limiters
            .createLinearGrowthLimiter(
                config.repayWithCollateralLimitMaximum,
                config.repayWithCollateralLimitBlocks,
                config.repayWithCollateralLimitMinimum
            );

        _supportedBaseTokens.add(baseToken);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function addYieldToken(
        address yieldToken,
        ISavvyAdminActions.YieldTokenConfig calldata config
    ) external onlySavvyPositionManager {
        Checker.checkArgument(
            config.maximumLoss < BPS + 1,
            "invalid maximumLoss"
        );
        Checker.checkArgument(
            config.creditUnlockBlocks > 0,
            "invalid creditUnlockBlocks"
        );

        Checker.checkState(
            !_supportedYieldTokens.contains(yieldToken),
            "same yield token already exists"
        );

        ITokenAdapter adapter = ITokenAdapter(config.adapter);

        Checker.checkState(
            yieldToken == adapter.token(),
            "invalid yield token address"
        );
        _checkSupportedBaseToken(adapter.baseToken());

        uint8 yieldTokenDecimals = TokenUtils.expectDecimals(yieldToken);
        Checker.checkArgument(
            yieldTokenDecimals < 19,
            "invalid token decimals"
        );

        _yieldTokens[yieldToken] = YieldTokenParams({
            decimals: yieldTokenDecimals,
            baseToken: adapter.baseToken(),
            adapter: config.adapter,
            maximumLoss: config.maximumLoss,
            maximumExpectedValue: config.maximumExpectedValue,
            creditUnlockRate: FIXED_POINT_SCALAR / config.creditUnlockBlocks,
            activeBalance: 0,
            harvestableBalance: 0,
            totalShares: 0,
            expectedValue: 0,
            accruedWeight: 0,
            pendingCredit: 0,
            distributedCredit: 0,
            lastDistributionBlock: 0,
            enabled: false
        });

        _supportedYieldTokens.add(yieldToken);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function setBaseTokenEnabled(
        address baseToken,
        bool enabled
    ) external onlySavvyPositionManager {
        _checkSupportedBaseToken(baseToken);
        _baseTokens[baseToken].enabled = enabled;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function setYieldTokenEnabled(
        address yieldToken,
        bool enabled
    ) external onlySavvyPositionManager {
        _checkSupportedYieldToken(yieldToken);
        _yieldTokens[yieldToken].enabled = enabled;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function configureRepayLimit(
        address baseToken,
        uint256 maximum,
        uint256 blocks
    ) external onlySavvyPositionManager {
        _checkSupportedBaseToken(baseToken);
        _repayLimiters[baseToken].update();
        _repayLimiters[baseToken].configure(maximum, blocks);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function configureRepayWithCollateralLimit(
        address baseToken,
        uint256 maximum,
        uint256 blocks
    ) external onlySavvyPositionManager {
        _checkSupportedBaseToken(baseToken);
        _repayWithCollateralLimiters[baseToken].update();
        _repayWithCollateralLimiters[baseToken].configure(maximum, blocks);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function configureBorrowingLimit(
        uint256 maximum,
        uint256 blocks
    ) external onlySavvyPositionManager {
        _borrowingLimiter.update();
        _borrowingLimiter.configure(maximum, blocks);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function configureCreditUnlockRate(
        address yieldToken,
        uint256 blocks
    ) external onlySavvyPositionManager {
        Checker.checkArgument(blocks > 0, "zero blocks");
        _checkSupportedYieldToken(yieldToken);
        _yieldTokens[yieldToken].creditUnlockRate = FIXED_POINT_SCALAR / blocks;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function setTokenAdapter(
        address yieldToken,
        address adapter
    ) external onlySavvyPositionManager {
        address oldAdapter = _yieldTokens[yieldToken].adapter;
        Checker.checkState(
            yieldToken == ITokenAdapter(adapter).token(),
            "invalid yield token address"
        );
        Checker.checkState(
            ITokenAdapter(oldAdapter).baseToken() ==
                ITokenAdapter(adapter).baseToken(),
            "invalid base token address"
        );
        _checkSupportedYieldToken(yieldToken);

        TokenUtils.safeApprove(yieldToken, oldAdapter, 0);
        TokenUtils.safeApprove(
            ITokenAdapter(oldAdapter).baseToken(),
            oldAdapter,
            0
        );

        TokenUtils.safeApprove(yieldToken, adapter, type(uint256).max);
        TokenUtils.safeApprove(
            ITokenAdapter(adapter).baseToken(),
            adapter,
            type(uint256).max
        );

        _yieldTokens[yieldToken].adapter = adapter;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function setMaximumExpectedValue(
        address yieldToken,
        uint256 value
    ) external onlySavvyPositionManager {
        _checkSupportedYieldToken(yieldToken);
        _yieldTokens[yieldToken].maximumExpectedValue = value;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function setMaximumLoss(
        address yieldToken,
        uint256 value
    ) external onlySavvyPositionManager {
        Checker.checkArgument(value < BPS + 1, "invalid maximumLoss");
        _checkSupportedYieldToken(yieldToken);

        _yieldTokens[yieldToken].maximumLoss = value;
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function distributeUnlockedCredit(
        address yieldToken
    ) external onlySavvyPositionManager {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        (, uint256 unlockedCredit) = calculateUnlockedCredit(yieldToken);
        if (unlockedCredit == 0) {
            return;
        }

        yieldTokenParams.accruedWeight +=
            (unlockedCredit * FIXED_POINT_SCALAR) /
            yieldTokenParams.totalShares;
        yieldTokenParams.distributedCredit += unlockedCredit;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function convertYieldTokensToShares(
        address yieldToken,
        uint256 amount
    ) public view returns (uint256) {
        YieldTokenParams memory yieldTokenParams = _yieldTokens[yieldToken];
        if (yieldTokenParams.totalShares == 0) {
            return amount * _getYieldTokenFixedPoint(yieldToken);
        }

        return
            (amount * yieldTokenParams.totalShares) /
            calculateUnrealizedActiveBalance(yieldToken);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function convertBaseTokensToShares(
        address yieldToken,
        uint256 amount
    ) public view returns (uint256) {
        uint256 amountYieldTokens = convertBaseTokensToYieldToken(
            yieldToken,
            amount
        );
        return convertYieldTokensToShares(yieldToken, amountYieldTokens);
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function snap(
        address yieldToken
    ) external onlySavvyPositionManager returns (uint256) {
        _checkSupportedYieldToken(yieldToken);

        uint256 expectedValue = convertYieldTokensToBaseToken(
            yieldToken,
            _yieldTokens[yieldToken].activeBalance
        );

        _yieldTokens[yieldToken].expectedValue = expectedValue;

        return expectedValue;
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function preemptivelyHarvest(
        address yieldToken
    ) public onlySavvyPositionManager {
        YieldTokenParams memory _yieldToken = _yieldTokens[yieldToken];
        uint256 activeBalance = _yieldToken.activeBalance;
        if (activeBalance == 0) {
            return;
        }

        uint256 currentValue = convertYieldTokensToBaseToken(
            yieldToken,
            activeBalance
        );
        uint256 expectedValue = _yieldToken.expectedValue;
        if (currentValue < expectedValue + 1) {
            emit HarvestExceedsOffset(yieldToken, currentValue, expectedValue);
            return;
        }

        uint256 harvestable = convertBaseTokensToYieldToken(
            yieldToken,
            currentValue - expectedValue
        );
        if (harvestable == 0) {
            return;
        }
        _preemptivelyHarvest(yieldToken, harvestable);
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function donate(
        address yieldToken,
        uint256 amount,
        uint256 shares
    ) external onlySavvyPositionManager returns (uint256) {
        return (_yieldTokens[yieldToken].accruedWeight +=
            (amount * FIXED_POINT_SCALAR) /
            shares);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function checkSupportTokens(address rewardToken) external view {
        require(
            !_supportedYieldTokens.contains(rewardToken) &&
                !_supportedBaseTokens.contains(rewardToken),
            "UnsupportedToken"
        );
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function repayWithBaseToken(
        address baseToken,
        uint256 amount,
        int256 debt
    ) external view onlySavvyPositionManager returns (uint256, uint256) {
        // Determine the maximum amount of base tokens that can be repaid.
        //
        // It is implied that this value is greater than zero because `debt` is greater than zero so a noop is not possible
        // beyond this point. Casting the debt to an unsigned integer is also safe because `debt` is greater than zero.
        uint256 maximumAmount = _normalizeDebtTokensToUnderlying(
            baseToken,
            uint256(debt)
        );

        // Limit the number of base tokens to repay up to the maximum allowed.
        uint256 actualAmount = amount > maximumAmount ? maximumAmount : amount;

        // Check to make sure that the base token repay limit has not been breached.
        uint256 _currentRepayWithBaseTokenLimit = _repayLimiters[baseToken]
            .get();
        require(
            actualAmount <= _currentRepayWithBaseTokenLimit,
            "RepayLimitExceeded"
        );

        uint256 credit = _normalizeBaseTokensToDebt(baseToken, actualAmount);

        return (credit, actualAmount);
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function unwrap(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) public onlySavvyPositionManager returns (uint256) {
        YieldTokenParams memory yieldTokenParams = _yieldTokens[yieldToken];
        ITokenAdapter adapter = ITokenAdapter(yieldTokenParams.adapter);
        TokenUtils.safeApprove(yieldToken, address(adapter), amount);
        uint256 amountUnwrapped = adapter.unwrap(amount, recipient);
        require(amountUnwrapped >= minimumAmountOut, "SlippageExceeded");
        return amountUnwrapped;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function checkLoss(address yieldToken) public view {
        uint256 loss = _loss(yieldToken);
        YieldTokenParams memory _yieldToken = _yieldTokens[yieldToken];
        uint256 maximumLoss = _yieldToken.maximumLoss;
        require(loss <= maximumLoss, "LossExceeded");
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function repayLimiters(
        address baseToken
    ) external view returns (Limiters.LinearGrowthLimiter memory) {
        return _repayLimiters[baseToken];
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function repayWithCollateralLimiters(
        address baseToken
    ) external view returns (Limiters.LinearGrowthLimiter memory) {
        return _repayWithCollateralLimiters[baseToken];
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getYieldTokenParams(
        address yieldToken
    ) public view returns (YieldTokenParams memory) {
        return _yieldTokens[yieldToken];
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function getBaseTokenParams(
        address baseToken
    ) external view returns (BaseTokenParams memory) {
        return _baseTokens[baseToken];
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function repayWithCollateral(
        address yieldToken,
        address recipient,
        uint256 shares,
        uint256 minimumAmountOut,
        int256 unrealizedDebt
    ) external onlySavvyPositionManager returns (uint256, uint256, uint256) {
        address baseToken = _yieldTokens[yieldToken].baseToken;
        // Determine the maximum amount of shares that can be repaidWithCollateral from the unrealized debt.
        //
        // It is implied that this value is greater than zero because `debt` is greater than zero. Casting the debt to an
        // unsigned integer is also safe for this reason.
        uint256 maximumShares = convertBaseTokensToShares(
            yieldToken,
            _normalizeDebtTokensToUnderlying(baseToken, uint256(unrealizedDebt))
        );

        // Limit the number of shares to repayWithCollateral up to the maximum allowed.
        uint256 actualShares = shares > maximumShares ? maximumShares : shares;

        // Unwrap the yield tokens that the shares are worth.
        uint256 amountYieldTokens = convertSharesToYieldTokens(
            yieldToken,
            actualShares
        );
        amountYieldTokens = TokenUtils.safeTransferFrom(
            yieldToken,
            msg.sender,
            address(this),
            amountYieldTokens
        );
        uint256 amountBaseTokens = unwrap(
            yieldToken,
            amountYieldTokens,
            recipient,
            minimumAmountOut
        );

        // Again, perform another noop check. It is possible that the amount of base tokens that were received by
        // unwrapping the yield tokens was zero because the amount of yield tokens to unwrap was too small.
        Checker.checkState(amountBaseTokens > 0, "zero base token amount");

        // Check to make sure that the base token repayWithCollateral limit has not been breached.
        uint256 repayWithCollateralLimit = _repayWithCollateralLimiters[
            baseToken
        ].get();
        require(
            amountBaseTokens <= repayWithCollateralLimit,
            "RepayWithCollateralLimitExceeded"
        );

        // Buffers any harvestable yield tokens. This will properly synchronize the balance which is held by users
        // and the balance which is held by the system. This is required for `_sync` to function correctly.
        preemptivelyHarvest(yieldToken);

        return (amountBaseTokens, amountYieldTokens, actualShares);
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function harvest(
        address yieldToken,
        uint256 minimumAmountOut,
        uint256 protocolFee
    )
        external
        onlySavvyPositionManager
        returns (
            address baseToken,
            uint256 amountBaseTokens,
            uint256 feeAmount,
            uint256 distributeAmount,
            uint256 credit
        )
    {
        _checkSupportedYieldToken(yieldToken);

        // Buffer any harvestable yield tokens. This will properly synchronize the balance which is held by users
        // and the balance which is held by the system to be harvested during this call.
        preemptivelyHarvest(yieldToken);

        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        // Load and proactively clear the amount of harvestable tokens so that future calls do not rely on stale data.
        // Because we cannot call an external unwrap until the amount of harvestable tokens has been calculated,
        // clearing this data immediately prevents any potential reentrancy attacks which would use stale harvest
        // buffer values.
        uint256 harvestableAmount = yieldTokenParams.harvestableBalance;
        yieldTokenParams.harvestableBalance = 0;

        // Check that the harvest will not be a no-op.
        Checker.checkState(harvestableAmount != 0, "zero harvestable amount");

        baseToken = yieldTokenParams.baseToken;
        amountBaseTokens = _unwrap(
            yieldToken,
            harvestableAmount,
            savvyPositionManager,
            minimumAmountOut
        );

        // Calculate how much of the unwrapped base tokens will be allocated for fees and distributed to users.
        feeAmount = (amountBaseTokens * protocolFee) / BPS;
        distributeAmount = amountBaseTokens - feeAmount;

        credit = _normalizeBaseTokensToDebt(baseToken, distributeAmount);

        // Distribute credit to all of the users who hold shares of the yield token.
        _distributeCredit(yieldToken, credit);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function currentBorrowingLimiter() external view returns (uint256) {
        return _borrowingLimiter.get();
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function currentRepayWithBaseTokenLimit(
        address baseToken
    ) external view returns (uint256) {
        return _repayLimiters[baseToken].get();
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function currentRepayWithCollateralLimit(
        address baseToken
    ) external view returns (uint256) {
        return _repayWithCollateralLimiters[baseToken].get();
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function setBorrowingLimiter(
        Limiters.LinearGrowthLimiter calldata borrowingLimiter_
    ) external {
        // This is first time so savvyPositionManager should be zero.
        require(savvyPositionManager == address(0), "Unauthorized");
        _borrowingLimiter = borrowingLimiter_;
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function syncYieldToken(
        address yieldToken,
        uint256 amount,
        bool addOperation
    ) external onlySavvyPositionManager returns (YieldTokenParams memory) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        uint256 amountBaseTokens = convertYieldTokensToBaseToken(
            yieldToken,
            amount
        );
        uint256 updatedActiveBalance = Math.uoperation(
            yieldTokenParams.activeBalance,
            amount,
            addOperation
        );
        uint256 updatedExpectedValue = Math.uoperation(
            yieldTokenParams.expectedValue,
            amountBaseTokens,
            addOperation
        );

        // _yieldStrategyManager.syncYieldToken(yieldToken, updatedActiveBalance, updatedExpectedValue);
        yieldTokenParams.activeBalance = updatedActiveBalance;
        yieldTokenParams.expectedValue = updatedExpectedValue;

        // Check that the maximum expected value has not been breached.
        Checker.checkState(
            yieldTokenParams.expectedValue <=
                yieldTokenParams.maximumExpectedValue,
            Errors.SPM_EXPECTED_VALUE_EXCEEDED
        );

        return yieldTokenParams;
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function burnShares(
        address yieldToken,
        uint256 shares
    ) external onlySavvyPositionManager {
        _yieldTokens[yieldToken].totalShares -= shares;
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function issueSharesForAmount(
        address yieldToken,
        uint256 amount
    ) external onlySavvyPositionManager returns (uint256 shares) {
        shares = convertYieldTokensToShares(yieldToken, amount);
        _yieldTokens[yieldToken].totalShares += shares;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function checkSupportedYieldToken(address yieldToken) external view {
        _checkSupportedYieldToken(yieldToken);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function checkSupportedBaseToken(address baseToken) external view {
        _checkSupportedBaseToken(baseToken);
        _checkBaseTokenEnabled(baseToken);
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function convertSharesToBaseTokens(
        address yieldToken,
        uint256 shares
    ) public view returns (address baseToken, uint256 amountBaseTokens) {
        YieldTokenParams memory yieldTokenParam = _yieldTokens[yieldToken];
        baseToken = yieldTokenParam.baseToken;
        uint256 amountYieldTokens = convertSharesToYieldTokens(
            yieldToken,
            shares
        );
        amountBaseTokens = convertYieldTokensToBaseToken(
            yieldToken,
            amountYieldTokens
        );
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function convertSharesToYieldTokens(
        address yieldToken,
        uint256 shares
    ) public view returns (uint256) {
        uint256 totalShares = _yieldTokens[yieldToken].totalShares;
        if (totalShares == 0) {
            return shares / _getYieldTokenFixedPoint(yieldToken);
        }
        return
            (shares * calculateUnrealizedActiveBalance(yieldToken)) /
            totalShares;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function convertYieldTokensToBaseToken(
        address yieldToken,
        uint256 amount
    ) public view returns (uint256) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];
        ITokenAdapter adapter = ITokenAdapter(yieldTokenParams.adapter);
        return (amount * adapter.price()) / 10 ** yieldTokenParams.decimals;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function calculateUnrealizedActiveBalance(
        address yieldToken
    ) public view returns (uint256) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        uint256 activeBalance = yieldTokenParams.activeBalance;
        if (activeBalance == 0) {
            return activeBalance;
        }

        uint256 currentValue = convertYieldTokensToBaseToken(
            yieldToken,
            activeBalance
        );
        uint256 expectedValue = yieldTokenParams.expectedValue;
        if (currentValue < expectedValue + 1) {
            return activeBalance;
        }

        uint256 harvestable = convertBaseTokensToYieldToken(
            yieldToken,
            currentValue - expectedValue
        );
        if (harvestable == 0) {
            return activeBalance;
        }

        return activeBalance - harvestable;
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function convertBaseTokensToYieldToken(
        address yieldToken,
        uint256 amount
    ) public view returns (uint256) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];
        ITokenAdapter adapter = ITokenAdapter(yieldTokenParams.adapter);
        return (amount * 10 ** yieldTokenParams.decimals) / adapter.price();
    }

    /// @inheritdoc IYieldStrategyManagerStates
    function calculateUnlockedCredit(
        address yieldToken
    )
        public
        view
        returns (uint256 currentAccruedWeight, uint256 unlockedCredit)
    {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];
        currentAccruedWeight = yieldTokenParams.accruedWeight;

        {
            uint256 pendingCredit = yieldTokenParams.pendingCredit;
            if (pendingCredit > 0) {
                uint256 creditUnlockRate = yieldTokenParams.creditUnlockRate;
                uint256 distributedCredit = yieldTokenParams.distributedCredit;
                uint256 lastDistributionBlock = yieldTokenParams
                    .lastDistributionBlock;

                uint256 percentUnlocked = (block.number -
                    lastDistributionBlock) * creditUnlockRate;

                unlockedCredit = percentUnlocked < FIXED_POINT_SCALAR
                    ? ((pendingCredit * percentUnlocked) / FIXED_POINT_SCALAR) -
                        distributedCredit
                    : pendingCredit - distributedCredit;
            }
        }

        currentAccruedWeight += unlockedCredit > 0
            ? (unlockedCredit * FIXED_POINT_SCALAR) /
                yieldTokenParams.totalShares
            : 0;
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function repayWithCollateralCheck(
        address yieldToken
    ) external view returns (address baseToken) {
        YieldTokenParams memory yieldTokenParams = _yieldTokens[yieldToken];
        baseToken = yieldTokenParams.baseToken;

        _checkSupportedYieldToken(yieldToken);
        _checkYieldTokenEnabled(yieldToken);
        _checkBaseTokenEnabled(baseToken);
        checkLoss(yieldToken);
    }

    /// @inheritdoc IYieldStrategyManagerActions
    function depositPrepare(
        address yieldToken
    ) external returns (YieldTokenParams memory yieldTokenParam) {
        yieldTokenParam = _yieldTokens[yieldToken];
        address baseToken = yieldTokenParam.baseToken;

        // Check that the yield token and it's base token are enabled. Disabling the yield token and/or the
        // base token prevents the system from holding more of the disabled yield token or base token.
        _checkYieldTokenEnabled(yieldToken);
        _checkBaseTokenEnabled(baseToken);

        // Check to assure that the token has not experienced a sudden unexpected loss. This prevents users from being
        // able to deposit funds and then have them siphoned if the price recovers.
        checkLoss(yieldToken);

        // Buffers any harvestable yield tokens. This will properly synchronize the balance which is held by users
        // and the balance which is held by the system to eventually be harvested.
        YieldTokenParams memory _yieldToken = _yieldTokens[yieldToken];
        uint256 activeBalance = _yieldToken.activeBalance;
        if (activeBalance == 0) {
            return yieldTokenParam;
        }

        uint256 currentValue = convertYieldTokensToBaseToken(
            yieldToken,
            activeBalance
        );
        uint256 expectedValue = _yieldToken.expectedValue;
        if (currentValue < expectedValue + 1) {
            return yieldTokenParam;
        }

        uint256 harvestable = convertBaseTokensToYieldToken(
            yieldToken,
            currentValue - expectedValue
        );
        if (harvestable == 0) {
            return yieldTokenParam;
        }
        _preemptivelyHarvest(yieldToken, harvestable);
    }

    /// @dev Checks if an address is a supported base token.
    ///
    /// If the address is not a supported yield token, this function will revert using a {UnsupportedToken} error.
    ///
    /// @param baseToken The address to check.
    function _checkSupportedBaseToken(address baseToken) internal view {
        require(_supportedBaseTokens.contains(baseToken), "UnsupportedToken");
    }

    /// @dev Checks if an address is a supported yield token.
    ///
    /// If the address is not a supported yield token, this function will revert using a {UnsupportedToken} error.
    ///
    /// @param yieldToken The address to check.
    function _checkSupportedYieldToken(address yieldToken) internal view {
        require(_supportedYieldTokens.contains(yieldToken), "UnsupportedToken");
    }

    /// @dev Unwraps `amount` of `yieldToken` into its base token.
    ///
    /// @param yieldToken       The address of the yield token to unwrap.
    /// @param amount           The amount of the yield token to wrap.
    /// @param minimumAmountOut The minimum amount of base tokens that are expected to be received from the
    ///                         operation.
    ///
    /// @return The amount of base tokens that resulted from the operation.
    function _unwrap(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) internal returns (uint256) {
        amount = TokenUtils.safeTransferFrom(
            yieldToken,
            msg.sender,
            address(this),
            amount
        );
        ITokenAdapter adapter = ITokenAdapter(_yieldTokens[yieldToken].adapter);
        TokenUtils.safeApprove(yieldToken, address(adapter), amount);
        uint256 amountUnwrapped = adapter.unwrap(amount, recipient);
        require(amountUnwrapped >= minimumAmountOut, "SlippageExceeded");
        return amountUnwrapped;
    }

    /// @dev Normalize `amount` of `baseToken` to a value which is comparable to units of the debt token.
    ///
    /// @param baseToken The address of the base token.
    /// @param amount          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function _normalizeBaseTokensToDebt(
        address baseToken,
        uint256 amount
    ) internal view returns (uint256) {
        return amount * _baseTokens[baseToken].conversionFactor;
    }

    /// @dev Distributes `amount` credit to all depositors of `yieldToken`.
    ///
    /// @param yieldToken The address of the yield token to distribute credit for.
    /// @param amount     The amount of credit to distribute in debt tokens.
    function _distributeCredit(address yieldToken, uint256 amount) internal {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        uint256 pendingCredit = yieldTokenParams.pendingCredit;
        uint256 distributedCredit = yieldTokenParams.distributedCredit;
        (, uint256 unlockedCredit) = calculateUnlockedCredit(yieldToken);
        uint256 lockedCredit = pendingCredit -
            (distributedCredit + unlockedCredit);

        // Distribute any unlocked credit before overriding it.
        if (unlockedCredit > 0) {
            yieldTokenParams.accruedWeight +=
                (unlockedCredit * FIXED_POINT_SCALAR) /
                yieldTokenParams.totalShares;
        }

        yieldTokenParams.pendingCredit = amount + lockedCredit;
        yieldTokenParams.distributedCredit = 0;
        yieldTokenParams.lastDistributionBlock = block.number;
    }

    /// @dev Checks if a yield token is enabled.
    ///
    /// @param yieldToken The address of the yield token.
    function _checkYieldTokenEnabled(address yieldToken) internal view {
        YieldTokenParams memory _yieldToken = _yieldTokens[yieldToken];
        require(_yieldToken.enabled, "TokenDisabled");
    }

    /// @dev Checks if an base token is enabled.
    ///
    /// @param baseToken The address of the base token.
    function _checkBaseTokenEnabled(address baseToken) internal view {
        BaseTokenParams memory _baseToken = _baseTokens[baseToken];
        require(_baseToken.enabled, "TokenDisabled");
    }

    /// @dev Normalize `amount` of the debt token to a value which is comparable to units of `baseToken`.
    ///
    /// @dev This operation will result in truncation of some of the least significant digits of `amount`. This
    ///      truncation amount will be the least significant N digits where N is the difference in decimals between
    ///      the debt token and the base token.
    ///
    /// @param baseToken The address of the base token.
    /// @param amount          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function _normalizeDebtTokensToUnderlying(
        address baseToken,
        uint256 amount
    ) internal view returns (uint256) {
        BaseTokenParams memory baseTokenParams = _baseTokens[baseToken];
        return amount / baseTokenParams.conversionFactor;
    }

    /// @dev Gets the amount of loss that `yieldToken` has incurred measured in basis points. When the expected
    ///      underlying value is less than the actual value, this will return zero.
    ///
    /// @param yieldToken The address of the yield token.
    ///
    /// @return The loss in basis points.
    function _loss(address yieldToken) internal view returns (uint256) {
        YieldTokenParams memory yieldTokenParams = _yieldTokens[yieldToken];

        uint256 amountBaseTokens = convertYieldTokensToBaseToken(
            yieldToken,
            yieldTokenParams.activeBalance
        );
        uint256 expectedUnderlyingValue = yieldTokenParams.expectedValue;

        if (amountBaseTokens == 0) {
            return 1;
        } else {
            return
                expectedUnderlyingValue > amountBaseTokens
                    ? ((expectedUnderlyingValue - amountBaseTokens) * BPS) /
                        expectedUnderlyingValue
                    : 0;
        }
    }

    function _preemptivelyHarvest(
        address yieldToken,
        uint256 harvestable
    ) internal {
        _yieldTokens[yieldToken].activeBalance -= harvestable;
        _yieldTokens[yieldToken].harvestableBalance += harvestable;
    }

    function _getYieldTokenFixedPoint(
        address yieldToken
    ) internal view returns (uint256) {
        YieldTokenParams memory yieldTokenParams = _yieldTokens[yieldToken];
        return 10 ** (18 - yieldTokenParams.decimals);
    }

    uint256[100] private __gap;
}

