// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./Initializable.sol";
import "./IERC20.sol";
import {Unauthorized, IllegalState, IllegalArgument} from "./Errors.sol";

import "./Multicall.sol";
import "./Mutex.sol";

import "./IYieldStrategyManager.sol";
import "./ISavvyPositionManager.sol";
import "./IERC20TokenReceiver.sol";
import "./ITokenAdapter.sol";
import "./IAllowlist.sol";
import "./ISavvyBooster.sol";
import "./ISavvyPriceFeed.sol";
import "./ISavvyRedlist.sol";

import "./SafeCast.sol";
import "./Sets.sol";
import "./TokenUtils.sol";
import "./Limiters.sol";
import "./Math.sol";
import "./Checker.sol";

/// @title  SavvyPositionManager
/// @author Savvy DeFi
contract SavvyPositionManager is
    ISavvyPositionManager,
    Initializable,
    Multicall,
    Mutex
{
    using Limiters for Limiters.LinearGrowthLimiter;
    using Sets for Sets.AddressSet;

    /// @notice Handle of YieldStrategyManager
    IYieldStrategyManager public _yieldStrategyManager;

    /// @notice The total number of users collateral weight
    int256 public totalDebtBalance;

    /// @notice The number of basis points there are to represent exactly 100%.
    uint256 public constant BPS = 10000;

    /// @notice The scalar used for conversion of integral numbers to fixed point numbers. Fixed point numbers in this
    ///         implementation have 18 decimals of resolution, meaning that 1 is represented as 1e18, 0.5 is
    ///         represented as 5e17, and 2 is represented as 2e18.
    uint256 public constant FIXED_POINT_SCALAR = 1e18;

    /// @notice The address of Savvy Redlist contract.
    address public savvyRedlist;

    /// @notice The redlist is active.
    /// @dev true/false = turn on/off
    bool public redlistActive;

    /// @notice ProtocolTokenRequired status.
    /// @dev true/false = required or not.
    bool public protocolTokenRequired;

    /// @inheritdoc ISavvyImmutables
    string public constant override version = "1.0.0";

    /// @inheritdoc ISavvyImmutables
    address public override debtToken;

    /// @inheritdoc ISavvyState
    address public override admin;

    /// @inheritdoc ISavvyState
    address public override pendingAdmin;

    /// @inheritdoc ISavvyState
    address public override wrapTokenGateway;

    /// @inheritdoc ISavvyState
    int256 public totalDebt;

    /// @inheritdoc ISavvyState
    mapping(address => bool) public override sentinels;

    /// @inheritdoc ISavvyState
    mapping(address => bool) public override keepers;

    /// @inheritdoc ISavvyState
    address public override savvySage;

    /// @inheritdoc ISavvyState
    address public override svyBooster;

    /// @inheritdoc ISavvyState
    uint256 public override minimumCollateralization;

    /// @inheritdoc ISavvyState
    uint256 public override protocolFee;

    /// @inheritdoc ISavvyState
    address public override protocolFeeReceiver;

    /// @inheritdoc ISavvyState
    address public override allowlist;

    address private baseToken;

    /// @dev Accounts mapped by the address that owns them.
    mapping(address => Account) private _accounts;

    /// @dev SvyPriceFeed contract address.
    address private svyPriceFeed;

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ISavvyState
    function yieldStrategyManager()
        external
        view
        returns (IYieldStrategyManager)
    {
        return _yieldStrategyManager;
    }

    /// @inheritdoc ISavvyState
    function supportInterface(
        bytes4 _interfaceId
    ) external pure returns (bool) {
        return _interfaceId == type(ISavvyAdminActions).interfaceId;
    }

    /// @inheritdoc ISavvyState
    function accounts(
        address owner
    )
        external
        view
        override
        returns (int256 debt, address[] memory depositedTokens)
    {
        Account storage account = _accounts[owner];

        return (
            _calculateUnrealizedDebt(owner),
            account.depositedTokens.values
        );
    }

    /// @inheritdoc ISavvyState
    function positions(
        address owner,
        address yieldToken
    )
        external
        view
        override
        returns (
            uint256 shares,
            uint256 harvestedYield,
            uint256 lastAccruedWeight
        )
    {
        Account storage account = _accounts[owner];
        return (
            account.balances[yieldToken],
            account.harvestedYield[yieldToken],
            account.lastAccruedWeights[yieldToken]
        );
    }

    /// @inheritdoc ISavvyState
    function borrowAllowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        Account storage account = _accounts[owner];
        return account.borrowAllowances[spender];
    }

    /// @inheritdoc ISavvyState
    function withdrawAllowance(
        address owner,
        address spender,
        address yieldToken
    ) external view override returns (uint256) {
        Account storage account = _accounts[owner];
        return account.withdrawAllowances[spender][yieldToken];
    }

    /// @inheritdoc ISavvyAdminActions
    function initialize(
        InitializationParams calldata params
    ) external initializer {
        Checker.checkArgument(
            params.protocolFee <= BPS,
            Errors.SPM_FEE_EXCEEDS_BPS
        );

        debtToken = params.debtToken;
        admin = params.admin;
        savvySage = params.savvySage;
        svyBooster = params.svyBooster;
        svyPriceFeed = params.svyPriceFeed;
        redlistActive = params.redlistActive;
        savvyRedlist = params.savvyRedlist;
        _yieldStrategyManager = IYieldStrategyManager(
            params.yieldStrategyManager
        );
        minimumCollateralization = params.minimumCollateralization;
        protocolFee = params.protocolFee;
        protocolFeeReceiver = params.protocolFeeReceiver;
        allowlist = params.allowlist;
        baseToken = params.baseToken;
        wrapTokenGateway = params.wrapTokenGateway;

        _yieldStrategyManager.setBorrowingLimiter(
            Limiters.createLinearGrowthLimiter(
                params.borrowingLimitMaximum,
                params.borrowingLimitBlocks,
                params.borrowingLimitMinimum
            )
        );

        emit AdminUpdated(admin);
        emit SavvySageUpdated(savvySage);
        emit MinimumCollateralizationUpdated(minimumCollateralization);
        emit ProtocolFeeUpdated(protocolFee);
        emit ProtocolFeeReceiverUpdated(protocolFeeReceiver);
        emit BorrowingLimitUpdated(
            params.borrowingLimitMaximum,
            params.borrowingLimitBlocks
        );
    }

    /// @inheritdoc ISavvyAdminActions
    function setRedlistActive(bool flag) external override {
        _onlyAdmin();
        redlistActive = flag;
        emit RedlistActiveUpdated(flag);
    }

    /// @inheritdoc ISavvyAdminActions
    function setProtocolTokenRequiredActive(bool flag) external override {
        _onlyAdmin();
        protocolTokenRequired = flag;
        emit ProtocolTokenRequiredActiveUpdated(flag);
    }

    /// @inheritdoc ISavvyAdminActions
    function setPendingAdmin(address value) external override {
        _onlyAdmin();
        pendingAdmin = value;
        emit PendingAdminUpdated(value);
    }

    /// @inheritdoc ISavvyAdminActions
    function acceptAdmin() external override {
        Checker.checkState(
            pendingAdmin != address(0),
            Errors.SPM_ZERO_ADMIN_ADDRESS
        );
        Checker.checkState(
            msg.sender == pendingAdmin,
            Errors.SPM_UNAUTHORIZED_PENDING_ADMIN
        );

        admin = pendingAdmin;
        pendingAdmin = address(0);

        emit AdminUpdated(admin);
        emit PendingAdminUpdated(address(0));
    }

    /// @inheritdoc ISavvyAdminActions
    function setSentinel(address sentinel, bool flag) external override {
        _onlyAdmin();
        sentinels[sentinel] = flag;
        emit SentinelSet(sentinel, flag);
    }

    /// @inheritdoc ISavvyAdminActions
    function setKeeper(address keeper, bool flag) external override {
        _onlyAdmin();
        keepers[keeper] = flag;
        emit KeeperSet(keeper, flag);
    }

    /// @inheritdoc ISavvyAdminActions
    function addBaseToken(
        address baseToken_,
        BaseTokenConfig calldata config
    ) external override lock {
        _onlyAdmin();

        _yieldStrategyManager.addBaseToken(debtToken, baseToken_, config);

        emit AddBaseToken(baseToken_);
    }

    /// @inheritdoc ISavvyAdminActions
    function addYieldToken(
        address yieldToken,
        YieldTokenConfig calldata config
    ) external override lock {
        _onlyAdmin();

        _yieldStrategyManager.addYieldToken(yieldToken, config);

        TokenUtils.safeApprove(yieldToken, config.adapter, type(uint256).max);
        TokenUtils.safeApprove(
            ITokenAdapter(config.adapter).baseToken(),
            config.adapter,
            type(uint256).max
        );

        TokenUtils.safeApprove(
            yieldToken,
            address(_yieldStrategyManager),
            type(uint256).max
        );
        TokenUtils.safeApprove(
            ITokenAdapter(config.adapter).baseToken(),
            address(_yieldStrategyManager),
            type(uint256).max
        );

        emit AddYieldToken(yieldToken);
        emit TokenAdapterUpdated(yieldToken, config.adapter);
        emit MaximumLossUpdated(yieldToken, config.maximumLoss);
    }

    /// @inheritdoc ISavvyAdminActions
    function setBaseTokenEnabled(
        address baseToken_,
        bool enabled
    ) external override {
        _onlySentinelOrAdmin();
        _yieldStrategyManager.setBaseTokenEnabled(baseToken_, enabled);
        emit BaseTokenEnabled(baseToken_, enabled);
    }

    /// @inheritdoc ISavvyAdminActions
    function setYieldTokenEnabled(
        address yieldToken,
        bool enabled
    ) external override {
        _onlySentinelOrAdmin();
        _yieldStrategyManager.setYieldTokenEnabled(yieldToken, enabled);
        emit YieldTokenEnabled(yieldToken, enabled);
    }

    /// @inheritdoc ISavvyAdminActions
    function configureRepayLimit(
        address baseToken_,
        uint256 maximum,
        uint256 blocks
    ) external override {
        _onlyAdmin();
        _yieldStrategyManager.configureRepayLimit(baseToken_, maximum, blocks);
        emit RepayLimitUpdated(baseToken_, maximum, blocks);
    }

    /// @inheritdoc ISavvyAdminActions
    function configureRepayWithCollateralLimit(
        address baseToken_,
        uint256 maximum,
        uint256 blocks
    ) external override {
        _onlyAdmin();
        _yieldStrategyManager.configureRepayWithCollateralLimit(
            baseToken_,
            maximum,
            blocks
        );
        emit RepayWithCollateralLimitUpdated(baseToken_, maximum, blocks);
    }

    /// @inheritdoc ISavvyAdminActions
    function setSavvySage(address _savvySage) external override {
        _onlyAdmin();
        Checker.checkArgument(
            _savvySage != address(0),
            Errors.SPM_ZERO_SAVVY_SAGE_ADDRESS
        );
        savvySage = _savvySage;
        emit SavvySageUpdated(_savvySage);
    }

    /// @inheritdoc ISavvyAdminActions
    function setMinimumCollateralization(uint256 value) external override {
        _onlyAdmin();
        minimumCollateralization = value;
        emit MinimumCollateralizationUpdated(value);
    }

    /// @inheritdoc ISavvyAdminActions
    function setProtocolFee(uint256 value) external override {
        _onlyAdmin();
        Checker.checkArgument(value <= BPS, Errors.SPM_FEE_EXCEEDS_BPS);
        protocolFee = value;
        emit ProtocolFeeUpdated(value);
    }

    /// @inheritdoc ISavvyAdminActions
    function setProtocolFeeReceiver(address value) external override {
        _onlyAdmin();
        Checker.checkArgument(
            value != address(0),
            Errors.SPM_ZERO_PROTOCOL_FEE_RECEIVER_ADDRESS
        );
        protocolFeeReceiver = value;
        emit ProtocolFeeReceiverUpdated(value);
    }

    /// @inheritdoc ISavvyAdminActions
    function configureBorrowingLimit(
        uint256 maximum,
        uint256 blocks
    ) external override {
        _onlyAdmin();
        _yieldStrategyManager.configureBorrowingLimit(maximum, blocks);
        emit BorrowingLimitUpdated(maximum, blocks);
    }

    /// @inheritdoc ISavvyAdminActions
    function configureCreditUnlockRate(
        address yieldToken,
        uint256 blocks
    ) external override {
        _onlyAdmin();
        _yieldStrategyManager.configureCreditUnlockRate(yieldToken, blocks);
        emit CreditUnlockRateUpdated(yieldToken, blocks);
    }

    /// @inheritdoc ISavvyAdminActions
    function setTokenAdapter(
        address yieldToken,
        address adapter
    ) external override {
        _onlyAdmin();
        _yieldStrategyManager.setTokenAdapter(yieldToken, adapter);
        emit TokenAdapterUpdated(yieldToken, adapter);
    }

    /// @inheritdoc ISavvyAdminActions
    function setMaximumExpectedValue(
        address yieldToken,
        uint256 value
    ) external override {
        _onlyAdmin();
        _yieldStrategyManager.setMaximumExpectedValue(yieldToken, value);
        emit MaximumExpectedValueUpdated(yieldToken, value);
    }

    /// @inheritdoc ISavvyAdminActions
    function setMaximumLoss(
        address yieldToken,
        uint256 value
    ) external override {
        _onlyAdmin();
        _yieldStrategyManager.setMaximumLoss(yieldToken, value);
        emit MaximumLossUpdated(yieldToken, value);
    }

    /// @inheritdoc ISavvyAdminActions
    function snap(address yieldToken) external override lock {
        _onlyAdmin();
        uint256 expectedValue = _yieldStrategyManager.snap(yieldToken);
        emit Snap(yieldToken, expectedValue);
    }

    /// @inheritdoc ISavvyAdminActions
    function sweepTokens(
        address rewardToken,
        uint256 amount
    ) external override lock {
        _onlyAdmin();

        _yieldStrategyManager.checkSupportTokens(rewardToken);

        TokenUtils.safeTransfer(rewardToken, admin, amount);

        emit SweepTokens(rewardToken, amount);
    }

    /// @inheritdoc ISavvyActions
    function approveBorrow(address spender, uint256 amount) external override {
        _onlyAllowlisted();
        Account storage account = _accounts[msg.sender];
        account.borrowAllowances[spender] = amount;
        emit ApproveBorrow(msg.sender, spender, amount);
    }

    /// @inheritdoc ISavvyActions
    function approveWithdraw(
        address spender,
        address yieldToken,
        uint256 shares
    ) external override {
        _onlyAllowlisted();
        _yieldStrategyManager.checkSupportedYieldToken(yieldToken);
        Account storage account = _accounts[msg.sender];
        account.withdrawAllowances[spender][yieldToken] = shares;
        emit ApproveWithdraw(msg.sender, spender, yieldToken, shares);
    }

    /// @inheritdoc ISavvyActions
    function syncAccount(address owner) external override lock {
        _onlyAllowlisted();
        _preemptivelyHarvestDeposited(owner);
        _distributeUnlockedCreditDeposited(owner);
        _syncAccount(owner);
    }

    /// @inheritdoc ISavvyActions
    function depositYieldToken(
        address yieldToken,
        uint256 amount,
        address recipient
    ) external override lock returns (uint256) {
        _checkDepositAvailable();
        Checker.checkArgument(
            recipient != address(0),
            Errors.SPM_ZERO_RECIPIENT_ADDRESS
        );
        _yieldStrategyManager.checkSupportedYieldToken(yieldToken);

        // Transfer tokens from the message sender now that the internal storage updates have been committed.
        amount = TokenUtils.safeTransferFrom(
            yieldToken,
            msg.sender,
            address(this),
            amount
        );

        // Deposit the yield tokens to the recipient.
        return _depositYieldToken(yieldToken, amount, recipient);
    }

    /// @inheritdoc ISavvyActions
    function depositBaseToken(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) external override lock returns (uint256) {
        _checkDepositAvailable();
        Checker.checkArgument(
            recipient != address(0),
            Errors.SPM_ZERO_RECIPIENT_ADDRESS
        );
        _yieldStrategyManager.checkSupportedYieldToken(yieldToken);

        // Before depositing, the base tokens must be wrapped into yield tokens.
        uint256 amountYieldTokens = _wrap(yieldToken, amount, minimumAmountOut);

        // Deposit the yield-tokens to the recipient.
        return _depositYieldToken(yieldToken, amountYieldTokens, recipient);
    }

    /// @inheritdoc ISavvyActions
    function withdrawYieldToken(
        address yieldToken,
        uint256 shares,
        address recipient
    ) external override lock returns (uint256) {
        return _withdrawYieldToken(msg.sender, yieldToken, shares, recipient);
    }

    /// @inheritdoc ISavvyActions
    function withdrawYieldTokenFrom(
        address owner,
        address yieldToken,
        uint256 shares,
        address recipient
    ) external override lock returns (uint256) {
        // Preemptively try and decrease the withdrawal allowance. This will save gas when the allowance is not
        // sufficient for the withdrawal.
        _decreaseWithdrawAllowance(owner, msg.sender, yieldToken, shares);

        return _withdrawYieldToken(owner, yieldToken, shares, recipient);
    }

    /// @inheritdoc ISavvyActions
    function withdrawBaseToken(
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) external override lock returns (uint256) {
        return
            _withdrawBaseToken(
                msg.sender,
                yieldToken,
                shares,
                recipient,
                minimumAmountOut
            );
    }

    /// @inheritdoc ISavvyActions
    function withdrawBaseTokenFrom(
        address owner,
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) external override lock returns (uint256) {
        _decreaseWithdrawAllowance(owner, msg.sender, yieldToken, shares);

        return
            _withdrawBaseToken(
                owner,
                yieldToken,
                shares,
                recipient,
                minimumAmountOut
            );
    }

    /// @inheritdoc ISavvyActions
    function borrowCredit(
        uint256 amount,
        address recipient
    ) external override lock {
        _borrowCredit(msg.sender, amount, recipient);
    }

    /// @inheritdoc ISavvyActions
    function borrowCreditFrom(
        address owner,
        uint256 amount,
        address recipient
    ) external override lock {
        // Preemptively try and decrease the borrowing allowance. This will save gas when the allowance is not sufficient
        // for the borrow.
        _decreaseBorrowAllowance(owner, msg.sender, amount);

        _borrowCredit(owner, amount, recipient);
    }

    /// @inheritdoc ISavvyActions
    function repayWithDebtToken(
        uint256 amount,
        address recipient
    ) external override lock returns (uint256) {
        _onlyAllowlisted();

        Checker.checkArgument(amount > 0, Errors.SPM_ZERO_TOKEN_AMOUNT);
        Checker.checkArgument(
            recipient != address(0),
            Errors.SPM_ZERO_RECIPIENT_ADDRESS
        );

        // Distribute unlocked credit to depositors.
        _distributeUnlockedCreditDeposited(recipient);

        // Update the recipient's account, decrease the debt of the recipient by the number of tokens burned.
        _syncAccount(recipient);

        // Check that the debt is greater than zero.
        //
        // It is possible that the number of debt which is repayable is equal to or less than zero after realizing the
        // credit that was earned since the last update. We do not want to perform a noop so we need to check that the
        // amount of debt to repay is greater than zero.
        int256 debt;
        Checker.checkState(
            (debt = _accounts[recipient].debt) > 0,
            Errors.SPM_INVALID_DEBT_AMOUNT
        );

        // Limit how much debt can be repaid up to the current amount of debt that the account has. This prevents
        // situations where the user may be trying to repay their entire debt, but it decreases since they send the
        // transaction and causes a revert because burning can never decrease the debt below zero.
        //
        // Casts here are safe because it is asserted that debt is greater than zero.
        uint256 credit = Math.min(amount, uint256(debt));

        // Update the recipient's debt.
        _updateDebt(recipient, -SafeCast.toInt256(credit));

        // Burn the tokens from the message sender.
        TokenUtils.safeBurnFrom(debtToken, msg.sender, credit);

        // Increase the global amount of borrowable debt tokens.
        // Do this after burning instead of before because borrowing limit increase is an action beneficial to the user.
        _yieldStrategyManager.increaseBorrowingLimiter(credit);

        emit RepayWithDebtToken(msg.sender, credit, recipient);

        return credit;
    }

    /// @inheritdoc ISavvyActions
    function repayWithBaseToken(
        address baseToken_,
        uint256 amount,
        address recipient
    ) external override lock returns (uint256) {
        _onlyAllowlisted();

        Checker.checkArgument(amount > 0, Errors.SPM_ZERO_TOKEN_AMOUNT);
        Checker.checkArgument(
            recipient != address(0),
            Errors.SPM_ZERO_RECIPIENT_ADDRESS
        );

        _yieldStrategyManager.checkSupportedBaseToken(baseToken_);

        // Distribute unlocked credit to depositors.
        _distributeUnlockedCreditDeposited(recipient);

        // Update the recipient's account and decrease the amount of debt incurred.
        _syncAccount(recipient);

        // Check that the debt is greater than zero.
        //
        // It is possible that the amount of debt which is repayable is equal to or less than zero after realizing the
        // credit that was earned since the last update. We do not want to perform a noop so we need to check that the
        // amount of debt to repay is greater than zero.
        int256 debt;
        Checker.checkState(
            (debt = _accounts[recipient].debt) > 0,
            Errors.SPM_INVALID_DEBT_AMOUNT
        );

        (uint256 credit, uint256 actualAmount) = _yieldStrategyManager
            .repayWithBaseToken(baseToken_, amount, debt);

        // Decrease the amount of the base token which is globally available to be repaid.
        _yieldStrategyManager.decreaseRepayWithBaseTokenLimiter(
            baseToken_,
            actualAmount
        );

        // Update the recipient's debt.
        _updateDebt(recipient, -SafeCast.toInt256(credit));

        // Transfer the repaid tokens to the savvySage.
        actualAmount = TokenUtils.safeTransferFrom(
            baseToken_,
            msg.sender,
            savvySage,
            actualAmount
        );

        // Inform the savvySage that it has received tokens.
        IERC20TokenReceiver(savvySage).onERC20Received(
            baseToken_,
            actualAmount
        );

        emit RepayWithBaseToken(
            msg.sender,
            baseToken_,
            actualAmount,
            recipient,
            credit
        );

        return actualAmount;
    }

    /// @inheritdoc ISavvyActions
    function repayWithCollateral(
        address yieldToken,
        uint256 shares,
        uint256 minimumAmountOut
    ) external override lock returns (uint256) {
        _onlyAllowlisted();

        Checker.checkArgument(shares > 0, Errors.SPM_ZERO_COLLATERAL_AMOUNT);

        address baseToken_ = _yieldStrategyManager.repayWithCollateralCheck(
            yieldToken
        );

        // Calculate the unrealized debt.
        //
        // It is possible that the number of debt which is repayable is equal to or less than zero after realizing the
        // credit that was earned since the last update. We do not want to perform a noop so we need to check that the
        // amount of debt to repay is greater than zero.
        int256 unrealizedDebt;
        Checker.checkState(
            (unrealizedDebt = _calculateUnrealizedDebt(msg.sender)) > 0,
            Errors.SPM_INVALID_UNREALIZED_DEBT_AMOUNT
        );

        TokenUtils.safeApprove(
            yieldToken,
            address(_yieldStrategyManager),
            type(uint256).max
        );
        (
            uint256 amountBaseTokens,
            uint256 amountYieldTokens,
            uint256 actualShares
        ) = _yieldStrategyManager.repayWithCollateral(
                yieldToken,
                address(this),
                shares,
                minimumAmountOut,
                unrealizedDebt
            );

        // Distribute unlocked credit to depositors.
        _distributeUnlockedCreditDeposited(msg.sender);

        uint256 credit = _normalizeBaseTokensToDebt(
            baseToken_,
            amountBaseTokens
        );

        // Update the message sender's account, proactively burn shares, decrease the amount of debt incurred, and then
        // decrease the value of the token that the system is expected to hold.
        _syncAccount(msg.sender, yieldToken);
        _burnShares(msg.sender, yieldToken, actualShares);
        _updateDebt(msg.sender, -SafeCast.toInt256(credit));

        _yieldStrategyManager.syncYieldToken(
            yieldToken,
            amountYieldTokens,
            false
        );

        // Decrease the amount of the base token which is globally available to be repaidWithCollateral.
        _yieldStrategyManager.decreaseRepayWithCollateralLimiter(
            baseToken_,
            amountBaseTokens
        );

        // Transfer the repaid tokens to the savvySage.
        TokenUtils.safeTransfer(baseToken_, savvySage, amountBaseTokens);

        // Inform the savvySage that it has received tokens.
        IERC20TokenReceiver(savvySage).onERC20Received(
            baseToken_,
            amountBaseTokens
        );

        emit RepayWithCollateral(
            msg.sender,
            yieldToken,
            baseToken_,
            actualShares,
            credit
        );

        return actualShares;
    }

    /// @inheritdoc ISavvyActions
    function donate(address yieldToken, uint256 amount) external override lock {
        _onlyAllowlisted();
        Checker.checkArgument(amount != 0, Errors.SPM_ZERO_TOKEN_AMOUNT);
        // Distribute any unlocked credit so that the accrued weight is up to date.
        _yieldStrategyManager.distributeUnlockedCredit(yieldToken);
        // Update the message sender's account. This will assure that any credit that was earned is not overridden.
        _syncAccount(msg.sender);
        YieldTokenParams memory _yieldToken = _yieldStrategyManager
            .getYieldTokenParams(yieldToken);
        uint256 shares = _yieldToken.totalShares -
            _accounts[msg.sender].balances[yieldToken];
        if (shares > 0) {
            _accounts[msg.sender].lastAccruedWeights[
                yieldToken
            ] = _yieldStrategyManager.donate(yieldToken, amount, shares);
        }
        TokenUtils.safeBurnFrom(debtToken, msg.sender, amount);
        // Increase the global amount of borrowable debt tokens.
        // Do this after burning instead of before because borrowing limit increase is an action beneficial to the user.
        _yieldStrategyManager.increaseBorrowingLimiter(amount);
        emit Donate(msg.sender, yieldToken, amount);
    }

    /// @inheritdoc ISavvyActions
    function harvest(
        address yieldToken,
        uint256 minimumAmountOut
    ) external override lock {
        _onlyKeeper();

        (
            address baseToken_,
            uint256 amountBaseTokens,
            uint256 feeAmount,
            uint256 distributeAmount,
            uint256 credit
        ) = _yieldStrategyManager.harvest(
                yieldToken,
                minimumAmountOut,
                protocolFee
            );

        // Transfer the tokens to the fee receiver and savvySage.
        TokenUtils.safeTransfer(baseToken_, protocolFeeReceiver, feeAmount);
        TokenUtils.safeTransfer(baseToken_, savvySage, distributeAmount);

        // Inform the savvySage that it has received tokens.
        IERC20TokenReceiver(savvySage).onERC20Received(
            baseToken_,
            distributeAmount
        );

        emit Harvest(yieldToken, minimumAmountOut, amountBaseTokens, credit);
    }

    /// @dev Update user collateral weight and total of them
    /// @dev userColWeight = sqrt([user’s total debt balance] x [user’s veSVY balance])
    /// @dev totalCollateralWeight = sqrt([total debt balance] x [total veSVY balance])
    /// @param _user The address of user should update collateral weight
    /// @param _oldDebt The debt amount before updated
    function _updateBooster(address _user, int256 _oldDebt) internal {
        int256 debt = _calculateUnrealizedDebt(_user);

        totalDebtBalance = totalDebtBalance - _oldDebt + debt;

        uint256 debtAmount = _getDebtTokenPrice(debt);
        uint256 totalDebtAmount = _getDebtTokenPrice(totalDebtBalance);

        ISavvyBooster(svyBooster).updatePendingRewardsWithDebt(
            _user,
            debtAmount,
            totalDebtAmount
        );
    }

    /// @dev Checks that the `msg.sender` is the administrator.
    ///
    /// @dev `msg.sender` must be the administrator or this call will revert with an {Unauthorized} error.
    function _onlyAdmin() internal view {
        Checker.checkState(msg.sender == admin, Errors.SPM_UNAUTHORIZED_ADMIN);
    }

    /// @dev Checks that the `msg.sender` is redlisted.
    ///
    /// @dev `msg.sender` must be redlisted or this call will revert with an {Unauthorized} error.
    ///
    /// @dev This function is not view because it updates the cache.
    function _onlyRedlisted() internal {
        Checker.checkState(
            msg.sender == wrapTokenGateway ||
                ((!redlistActive && !protocolTokenRequired) ||
                    ISavvyRedlist(savvyRedlist).isRedlisted(
                        msg.sender,
                        redlistActive,
                        protocolTokenRequired
                    )),
            Errors.SPM_UNAUTHORIZED_REDLIST
        );
    }

    /// @dev Checks that the `msg.sender` is the administrator or a sentinel.
    ///
    /// @dev `msg.sender` must be either the administrator or a sentinel or this call will revert with an
    ///      {Unauthorized} error.
    function _onlySentinelOrAdmin() internal view {
        // Check if the message sender is the administrator.
        // Check if the message sender is a sentinel. After this check we can revert since we know that it is neither
        // the administrator or a sentinel.
        Checker.checkState(
            msg.sender == admin || sentinels[msg.sender],
            Errors.SPM_UNAUTHORIZED_SENTINEL_OR_ADMIN
        );
    }

    /// @dev Checks that the `msg.sender` is a keeper.
    ///
    /// @dev `msg.sender` must be a keeper or this call will revert with an {Unauthorized} error.
    function _onlyKeeper() internal view {
        Checker.checkState(keepers[msg.sender], Errors.SPM_UNAUTHORIZED_KEEPER);
    }

    /// @dev Preemptively harvests all of the yield tokens that have been deposited into an account.
    ///
    /// @param owner The address which owns the account.
    function _preemptivelyHarvestDeposited(address owner) internal {
        Sets.AddressSet storage depositedTokens = _accounts[owner]
            .depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; i++) {
            _yieldStrategyManager.preemptivelyHarvest(
                depositedTokens.values[i]
            );
        }
    }

    /// @dev Checks if `amount` of debt tokens can be borrowed.
    ///
    /// @dev `amount` must be less than the current borrowing limit or this call will revert with a
    ///      {BorrowingLimitExceeded} error.
    ///
    /// @param amount The amount to check.
    function _checkBorrowingLimit(uint256 amount) internal view {
        uint256 limit = _yieldStrategyManager.currentBorrowingLimiter();
        Checker.checkState(
            amount <= limit,
            Errors.SPM_BORROWING_LIMIT_EXCEEDED
        );
    }

    /// @dev Deposits `amount` yield tokens into the account of `recipient`.
    ///
    /// @dev Emits a {Deposit} event.
    ///
    /// @param yieldToken The address of the yield token to deposit.
    /// @param amount     The amount of yield tokens to deposit.
    /// @param recipient  The recipient of the yield tokens.
    ///
    /// @return The number of shares borrowed to `recipient`.
    function _depositYieldToken(
        address yieldToken,
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        Checker.checkArgument(amount > 0, Errors.SPM_INVALID_TOKEN_AMOUNT);

        YieldTokenParams memory yieldTokenParams = _yieldStrategyManager
            .depositPrepare(yieldToken);

        // Distribute unlocked credit to depositors.
        _distributeUnlockedCreditDeposited(recipient);

        // Update the recipient's account, proactively issue shares for the deposited tokens to the recipient, and then
        // increase the value of the token that the system is expected to hold.
        _syncAccount(recipient, yieldToken);
        uint256 shares = _issueSharesForAmount(recipient, yieldToken, amount);

        // Get last yieldTokenParams.
        yieldTokenParams = _yieldStrategyManager.syncYieldToken(
            yieldToken,
            amount,
            true
        );

        emit DepositYieldToken(msg.sender, yieldToken, amount, recipient);

        return shares;
    }

    /// @dev Withdraw `yieldToken` from the account owned by `owner` by burning shares and receiving yield tokens of
    ///      equivalent value.
    ///
    /// @dev Emits a {Withdraw} event.
    ///
    /// @param yieldToken The address of the yield token to withdraw.
    /// @param owner      The address of the account owner to withdraw from.
    /// @param shares     The number of shares to burn.
    /// @param recipient  The recipient of the withdrawn shares. This parameter is only used for logging.
    ///
    /// @return The amount of yield tokens that the burned shares were exchanged for.
    function _withdraw(
        address yieldToken,
        address owner,
        uint256 shares,
        address recipient
    ) internal returns (uint256) {
        // Buffers any harvestable yield tokens that the owner of the account has deposited. This will properly
        // synchronize the balance of all the tokens held by the owner so that the validation check properly
        // computes the total value of the tokens held by the owner.
        _preemptivelyHarvestDeposited(owner);

        // Distribute unlocked credit for all of the tokens that the user has deposited into the system. This updates
        // the accrued weights so that the debt is properly calculated before the account is validated.
        _distributeUnlockedCreditDeposited(owner);

        uint256 amountYieldTokens = _yieldStrategyManager
            .convertSharesToYieldTokens(yieldToken, shares);

        // Update the owner's account, burn shares from the owner's account, and then decrease the value of the token
        // that the system is expected to hold.
        _syncAccount(owner);
        _burnShares(owner, yieldToken, shares);
        _yieldStrategyManager.syncYieldToken(
            yieldToken,
            amountYieldTokens,
            false
        );

        // Valid the owner's account to assure that the collateralization invariant is still held.
        _validateCollateralization(owner);

        emit WithdrawYieldToken(owner, yieldToken, shares, recipient);

        return amountYieldTokens;
    }

    /// @dev Distributes unlocked credit for all of the yield tokens that have been deposited into the account owned by `owner`.
    ///
    /// @param owner The address of the account owner.
    function _distributeUnlockedCreditDeposited(address owner) internal {
        Sets.AddressSet storage depositedTokens = _accounts[owner]
            .depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; i++) {
            _yieldStrategyManager.distributeUnlockedCredit(
                depositedTokens.values[i]
            );
        }
    }

    /// @dev Wraps `amount` of an base token into its `yieldToken`.
    ///
    /// @param yieldToken       The address of the yield token to wrap the base tokens into.
    /// @param amount           The amount of the base token to wrap.
    /// @param minimumAmountOut The minimum amount of yield tokens that are expected to be received from the operation.
    ///
    /// @return The amount of yield tokens that resulted from the operation.
    function _wrap(
        address yieldToken,
        uint256 amount,
        uint256 minimumAmountOut
    ) internal returns (uint256) {
        YieldTokenParams memory yieldTokenParams = _yieldStrategyManager
            .getYieldTokenParams(yieldToken);

        ITokenAdapter adapter = ITokenAdapter(yieldTokenParams.adapter);
        address baseToken_ = yieldTokenParams.baseToken;

        amount = TokenUtils.safeTransferFrom(
            baseToken_,
            msg.sender,
            address(this),
            amount
        );
        uint256 wrappedShares = adapter.wrap(amount, address(this));
        Checker.checkState(
            wrappedShares >= minimumAmountOut,
            Errors.SPM_SLIPPAGE_EXCEEDED
        );

        return wrappedShares;
    }

    /// @dev Synchronizes the state for all of the tokens deposited in the account owned by `owner`.
    ///
    /// @param owner The address of the account owner.
    function _syncAccount(address owner) internal {
        Sets.AddressSet storage depositedTokens = _accounts[owner]
            .depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; i++) {
            _syncAccount(owner, depositedTokens.values[i]);
        }
    }

    /// @dev Synchronizes the state of `yieldToken` for the account owned by `owner`.
    ///
    /// @param owner      The address of the account owner.
    /// @param yieldToken The address of the yield token to synchronize the state for.
    function _syncAccount(address owner, address yieldToken) internal {
        Account storage account = _accounts[owner];

        YieldTokenParams memory yieldTokenParams = _yieldStrategyManager
            .getYieldTokenParams(yieldToken);
        uint256 currentAccruedWeight = yieldTokenParams.accruedWeight;
        uint256 lastAccruedWeight = account.lastAccruedWeights[yieldToken];

        if (currentAccruedWeight == lastAccruedWeight) {
            return;
        }

        uint256 balance = account.balances[yieldToken];
        uint256 unrealizedCredit = ((currentAccruedWeight - lastAccruedWeight) *
            balance) / FIXED_POINT_SCALAR;

        _updateDebt(owner, -SafeCast.toInt256(unrealizedCredit));
        account.harvestedYield[yieldToken] += unrealizedCredit;
        account.lastAccruedWeights[yieldToken] = currentAccruedWeight;
    }

    /// @dev Increases the debt by `amount` for the account owned by `owner`.
    ///
    /// @param owner     The address of the account owner.
    /// @param amount    The amount to increase the debt by.
    function _updateDebt(address owner, int256 amount) internal {
        int256 oldDebt = _calculateUnrealizedDebt(owner);
        Account storage account = _accounts[owner];
        account.debt += amount;
        totalDebt += amount;
        _updateBooster(owner, oldDebt);
    }

    /// @dev Decrease the borrow allowance for `spender` by `amount` for the account owned by `owner`.
    ///
    /// @param owner   The address of the account owner.
    /// @param spender The address of the spender.
    /// @param amount  The amount of debt tokens to decrease the borrow allowance by.
    function _decreaseBorrowAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        Account storage account = _accounts[owner];
        account.borrowAllowances[spender] -= amount;
    }

    /// @dev Decrease the withdraw allowance of `yieldToken` for `spender` by `amount` for the account owned by `owner`.
    ///
    /// @param owner      The address of the account owner.
    /// @param spender    The address of the spender.
    /// @param yieldToken The address of the yield token to decrease the withdraw allowance for.
    /// @param amount     The amount of shares to decrease the withdraw allowance by.
    function _decreaseWithdrawAllowance(
        address owner,
        address spender,
        address yieldToken,
        uint256 amount
    ) internal {
        Account storage account = _accounts[owner];
        account.withdrawAllowances[spender][yieldToken] -= amount;
    }

    /// @dev Checks that the account owned by `owner` is properly collateralized.
    ///
    /// @dev If the account is undercollateralized then this will revert with an {Undercollateralized} error.
    ///
    /// @param owner The address of the account owner.
    function _validateCollateralization(address owner) internal view {
        int256 debt = _accounts[owner].debt;
        if (debt <= 0) {
            return;
        }

        uint256 collateralization = (_totalValue(owner) * FIXED_POINT_SCALAR) /
            uint256(debt);

        Checker.checkState(
            collateralization >= minimumCollateralization,
            Errors.SPM_UNDERCOLLATERALIZED
        );
    }

    /// @dev Gets the total value of the deposit collateral measured in debt tokens of the account owned by `owner`.
    ///
    /// @param owner The address of the account owner.
    ///
    /// @return The total value.
    function _totalValue(address owner) internal view returns (uint256) {
        uint256 totalValue = 0;

        Sets.AddressSet storage depositedTokens = _accounts[owner]
            .depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; i++) {
            address yieldToken = depositedTokens.values[i];
            uint256 shares = _accounts[owner].balances[yieldToken];
            (
                address baseToken_,
                uint256 amountBaseTokens
            ) = _yieldStrategyManager.convertSharesToBaseTokens(
                    yieldToken,
                    shares
                );

            totalValue += _normalizeBaseTokensToDebt(
                baseToken_,
                amountBaseTokens
            );
        }

        return totalValue;
    }

    /// @dev Issues shares of `yieldToken` for `amount` of its base token to `recipient`.
    ///
    /// IMPORTANT: `amount` must never be 0.
    ///
    /// @param recipient  The address of the recipient.
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of the base token.
    ///
    /// @return The amount of shares issued to `recipient`.
    function _issueSharesForAmount(
        address recipient,
        address yieldToken,
        uint256 amount
    ) internal returns (uint256) {
        if (_accounts[recipient].balances[yieldToken] == 0) {
            _accounts[recipient].depositedTokens.add(yieldToken);
        }

        uint256 shares = _yieldStrategyManager.issueSharesForAmount(
            yieldToken,
            amount
        );
        _accounts[recipient].balances[yieldToken] += shares;

        return shares;
    }

    /// @dev Burns `share` shares of `yieldToken` from the account owned by `owner`.
    ///
    /// @param owner      The address of the owner.
    /// @param yieldToken The address of the yield token.
    /// @param shares     The amount of shares to burn.
    function _burnShares(
        address owner,
        address yieldToken,
        uint256 shares
    ) internal {
        Account storage account = _accounts[owner];

        account.balances[yieldToken] -= shares;
        _yieldStrategyManager.burnShares(yieldToken, shares);

        if (account.balances[yieldToken] == 0) {
            account.depositedTokens.remove(yieldToken);
        }
    }

    /// @dev Gets the amount of debt that the account owned by `owner` will have after an update occurs.
    ///
    /// @param owner The address of the account owner.
    ///
    /// @return The amount of debt that the account owned by `owner` will have after an update.
    function _calculateUnrealizedDebt(
        address owner
    ) internal view returns (int256) {
        int256 debt = _accounts[owner].debt;

        Sets.AddressSet storage depositedTokens = _accounts[owner]
            .depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; i++) {
            address yieldToken = depositedTokens.values[i];

            (uint256 currentAccruedWeight, ) = _yieldStrategyManager
                .calculateUnlockedCredit(yieldToken);
            uint256 lastAccruedWeight = _accounts[owner].lastAccruedWeights[
                yieldToken
            ];

            if (currentAccruedWeight == lastAccruedWeight) {
                continue;
            }

            uint256 balance = _accounts[owner].balances[yieldToken];
            uint256 unrealizedCredit = ((currentAccruedWeight -
                lastAccruedWeight) * balance) / FIXED_POINT_SCALAR;

            debt -= SafeCast.toInt256(unrealizedCredit);
        }

        return debt;
    }

    /// @dev Checks the allowlist for msg.sender.
    ///
    /// Reverts if msg.sender is not in the allowlist.
    function _onlyAllowlisted() internal view {
        // Check if the message sender is an EOA. In the future, this potentially may break. It is important that functions
        // which rely on the allowlist not be explicitly vulnerable in the situation where this no longer holds true.
        // Only check the allowlist for calls from contracts.
        Checker.checkState(
            tx.origin == msg.sender ||
                IAllowlist(allowlist).isAllowed(msg.sender),
            Errors.SPM_UNAUTHORIZED_NOT_ALLOWLISTED
        );
    }

    /// @notice Withdraw base tokens to `recipient` by burning `share` shares from the account of `owner` and unwrapping the yield tokens that the shares were redeemed for.
    /// @param owner            The address of the account owner to withdraw from.
    /// @param yieldToken       The address of the yield token to withdraw.
    /// @param shares           The number of shares to burn.
    /// @param recipient        The address of the recipient.
    /// @param minimumAmountOut The minimum amount of base tokens that are expected to be withdrawn to `recipient`.
    ///
    /// @return amountWithdrawn The number of base tokens that were withdrawn to `recipient`.
    function _withdrawBaseToken(
        address owner,
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) internal returns (uint256) {
        Checker.checkArgument(
            recipient != address(0),
            Errors.SPM_ZERO_RECIPIENT_ADDRESS
        );

        _yieldStrategyManager.checkSupportedYieldToken(yieldToken);
        _yieldStrategyManager.checkLoss(yieldToken);

        uint256 amountYieldTokens = _withdraw(
            yieldToken,
            owner,
            shares,
            recipient
        );

        TokenUtils.safeTransfer(
            yieldToken,
            address(_yieldStrategyManager),
            amountYieldTokens
        );
        return
            _yieldStrategyManager.unwrap(
                yieldToken,
                amountYieldTokens,
                recipient,
                minimumAmountOut
            );
    }

    /// @notice Withdraw yield tokens to `recipient` by burning `share` shares.
    /// @dev The number of yield tokens withdrawn to `recipient` will depend on the value of shares for that yield token at the time of the call.
    /// @param owner            The address of the account owner to withdraw from.
    /// @param yieldToken       The address of the yield token to withdraw.
    /// @param shares           The number of shares to burn.
    /// @param recipient        The address of the recipient.
    /// @return The number of yield tokens that were withdrawn to `recipient`.
    function _withdrawYieldToken(
        address owner,
        address yieldToken,
        uint256 shares,
        address recipient
    ) internal returns (uint256) {
        Checker.checkArgument(
            recipient != address(0),
            Errors.SPM_ZERO_RECIPIENT_ADDRESS
        );
        _yieldStrategyManager.checkSupportedYieldToken(yieldToken);

        uint256 amountYieldTokens = _withdraw(
            yieldToken,
            owner,
            shares,
            recipient
        );
        TokenUtils.safeTransfer(yieldToken, recipient, amountYieldTokens);

        return amountYieldTokens;
    }

    /// @notice Borrow `amount` debt tokens from the account owned by `owner` to `recipient`.
    /// @param owner     The address of the owner of the account to borrow from.
    /// @param amount    The amount of tokens to borrow.
    /// @param recipient The address of the recipient.
    function _borrowCredit(
        address owner,
        uint256 amount,
        address recipient
    ) internal {
        _onlyAllowlisted();
        Checker.checkArgument(amount > 0, Errors.SPM_ZERO_TOKEN_AMOUNT);
        Checker.checkArgument(
            recipient != address(0),
            Errors.SPM_ZERO_RECIPIENT_ADDRESS
        );

        // Borrow tokens from the owner's account to the recipient.
        // Check that the system will allow for the specified amount to be borrowed.
        _checkBorrowingLimit(amount);

        // Preemptively harvest all tokens that the user has deposited into the system. This allows the debt to be
        // properly calculated before the account is validated.
        _preemptivelyHarvestDeposited(owner);

        // Distribute unlocked credit for all of the tokens that the user has deposited into the system. This updates
        // the accrued weights so that the debt is properly calculated before the account is validated.
        _distributeUnlockedCreditDeposited(owner);

        // Update the owner's account, increase their debt by the amount of tokens to borrow, and then finally validate
        // their account to assure that the collateralization invariant is still held.
        _syncAccount(owner);
        _updateDebt(owner, SafeCast.toInt256(amount));
        _validateCollateralization(owner);

        // Decrease the global amount of borrowable debt tokens.
        _yieldStrategyManager.decreaseBorrowingLimiter(amount);

        // Borrow the debt tokens to the recipient.
        TokenUtils.safeMint(debtToken, recipient, amount);

        emit Borrow(owner, amount, recipient);
    }

    /// @notice Get amount of debt token calculated by USD.
    /// @param debtAmount The address of a user.
    /// @return USD amount
    function _getDebtTokenPrice(
        int256 debtAmount
    ) internal view returns (uint256) {
        if (debtAmount <= 0) {
            return 0;
        }

        uint256 baseTokenAmount = _normalizeDebtTokensToBaseToken(
            baseToken,
            uint256(debtAmount)
        );
        return
            ISavvyPriceFeed(svyPriceFeed).getBaseTokenPrice(
                baseToken,
                baseTokenAmount
            );
    }

    /// @dev Normalize `amount` of `baseToken` to a value which is comparable to units of the debt token.
    ///
    /// @param baseToken_ The address of the base token.
    /// @param amount          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function _normalizeBaseTokensToDebt(
        address baseToken_,
        uint256 amount
    ) internal view returns (uint256) {
        BaseTokenParams memory baseTokenParams = _yieldStrategyManager
            .getBaseTokenParams(baseToken_);
        return amount * baseTokenParams.conversionFactor;
    }

    /// @dev Normalize `amount` of the debt token to a value which is comparable to units of `baseToken`.
    ///
    /// @dev This operation will result in truncation of some of the least significant digits of `amount`. This
    ///      truncation amount will be the least significant N digits where N is the difference in decimals between
    ///      the debt token and the base token.
    ///
    /// @param baseToken_ The address of the base token.
    /// @param amount          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function _normalizeDebtTokensToBaseToken(
        address baseToken_,
        uint256 amount
    ) internal view returns (uint256) {
        BaseTokenParams memory baseTokenParams = _yieldStrategyManager
            .getBaseTokenParams(baseToken_);
        return amount / baseTokenParams.conversionFactor;
    }

    /// @notice To deposit depositor is allowelisted and have proper tokens.
    function _checkDepositAvailable() internal {
        _onlyAllowlisted();
        _onlyRedlisted();
    }

    uint256[100] private __gap;
}

