// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  ISavvyEvents
/// @author Savvy DeFi
interface ISavvyEvents {
    /// @notice Emitted when the pending admin is updated.
    ///
    /// @param pendingAdmin The address of the pending admin.
    event PendingAdminUpdated(address pendingAdmin);

    /// @notice Emitted when the administrator is updated.
    ///
    /// @param admin The address of the administrator.
    event AdminUpdated(address admin);

    /// @notice Emitted when an address is set or unset as a sentinel.
    ///
    /// @param sentinel The address of the sentinel.
    /// @param flag     A flag indicating if `sentinel` was set or unset as a sentinel.
    event SentinelSet(address sentinel, bool flag);

    /// @notice Emitted when an address is set or unset as a keeper.
    ///
    /// @param sentinel The address of the keeper.
    /// @param flag     A flag indicating if `keeper` was set or unset as a sentinel.
    event KeeperSet(address sentinel, bool flag);

    /// @notice Emitted when an base token is added.
    ///
    /// @param baseToken The address of the base token that was added.
    event AddBaseToken(address indexed baseToken);

    /// @notice Emitted when a yield token is added.
    ///
    /// @param yieldToken The address of the yield token that was added.
    event AddYieldToken(address indexed yieldToken);

    /// @notice Emitted when an base token is enabled or disabled.
    ///
    /// @param baseToken The address of the base token that was enabled or disabled.
    /// @param enabled         A flag indicating if the base token was enabled or disabled.
    event BaseTokenEnabled(address indexed baseToken, bool enabled);

    /// @notice Emitted when an yield token is enabled or disabled.
    ///
    /// @param yieldToken The address of the yield token that was enabled or disabled.
    /// @param enabled    A flag indicating if the yield token was enabled or disabled.
    event YieldTokenEnabled(address indexed yieldToken, bool enabled);

    /// @notice Emitted when the repay limit of an base token is updated.
    ///
    /// @param baseToken The address of the base token.
    /// @param maximum         The updated maximum repay limit.
    /// @param blocks          The updated number of blocks it will take for the maximum repayment limit to be replenished when it is completely exhausted.
    event RepayLimitUpdated(
        address indexed baseToken,
        uint256 maximum,
        uint256 blocks
    );

    /// @notice Emitted when the repayWithCollateral limit of an base token is updated.
    ///
    /// @param baseToken The address of the base token.
    /// @param maximum         The updated maximum repayWithCollateral limit.
    /// @param blocks          The updated number of blocks it will take for the maximum repayWithCollateral limit to be replenished when it is completely exhausted.
    event RepayWithCollateralLimitUpdated(
        address indexed baseToken,
        uint256 maximum,
        uint256 blocks
    );

    /// @notice Emitted when the savvySage is updated.
    ///
    /// @param savvySage The updated address of the savvySage.
    event SavvySageUpdated(address savvySage);

    /// @notice Emitted when the minimum collateralization is updated.
    ///
    /// @param minimumCollateralization The updated minimum collateralization.
    event MinimumCollateralizationUpdated(uint256 minimumCollateralization);

    /// @notice Emitted when the protocol fee is updated.
    ///
    /// @param protocolFee The updated protocol fee.
    event ProtocolFeeUpdated(uint256 protocolFee);

    /// @notice Emitted when the protocol fee receiver is updated.
    ///
    /// @param protocolFeeReceiver The updated address of the protocol fee receiver.
    event ProtocolFeeReceiverUpdated(address protocolFeeReceiver);

    /// @notice Emitted when the borrowing limit is updated.
    ///
    /// @param maximum The updated maximum borrowing limit.
    /// @param blocks  The updated number of blocks it will take for the maximum borrowing limit to be replenished when it is completely exhausted.
    event BorrowingLimitUpdated(uint256 maximum, uint256 blocks);

    /// @notice Emitted when the credit unlock rate is updated.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param blocks     The number of blocks that distributed credit will unlock over.
    event CreditUnlockRateUpdated(address yieldToken, uint256 blocks);

    /// @notice Emitted when the adapter of a yield token is updated.
    ///
    /// @param yieldToken   The address of the yield token.
    /// @param tokenAdapter The updated address of the token adapter.
    event TokenAdapterUpdated(address yieldToken, address tokenAdapter);

    /// @notice Emitted when the maximum expected value of a yield token is updated.
    ///
    /// @param yieldToken           The address of the yield token.
    /// @param maximumExpectedValue The updated maximum expected value.
    event MaximumExpectedValueUpdated(
        address indexed yieldToken,
        uint256 maximumExpectedValue
    );

    /// @notice Emitted when the maximum loss of a yield token is updated.
    ///
    /// @param yieldToken  The address of the yield token.
    /// @param maximumLoss The updated maximum loss.
    event MaximumLossUpdated(address indexed yieldToken, uint256 maximumLoss);

    /// @notice Emitted when the expected value of a yield token is snapped to its current value.
    ///
    /// @param yieldToken    The address of the yield token.
    /// @param expectedValue The updated expected value measured in the yield token's base token.
    event Snap(address indexed yieldToken, uint256 expectedValue);

    /// @notice Emitted when a the admin sweeps all of one reward token from the Savvy
    ///
    /// @param rewardToken The address of the reward token.
    /// @param amount      The amount of 'rewardToken' swept into the admin.
    event SweepTokens(address indexed rewardToken, uint256 amount);

    /// @notice Emitted when `owner` grants `spender` the ability to borrow debt tokens on its behalf.
    ///
    /// @param owner   The address of the account owner.
    /// @param spender The address which is being permitted to borrow tokens on the behalf of `owner`.
    /// @param amount  The amount of debt tokens that `spender` is allowed to borrow.
    event ApproveBorrow(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when `owner` grants `spender` the ability to withdraw `yieldToken` from its account.
    ///
    /// @param owner      The address of the account owner.
    /// @param spender    The address which is being permitted to borrow tokens on the behalf of `owner`.
    /// @param yieldToken The address of the yield token that `spender` is allowed to withdraw.
    /// @param amount     The amount of shares of `yieldToken` that `spender` is allowed to withdraw.
    event ApproveWithdraw(
        address indexed owner,
        address indexed spender,
        address indexed yieldToken,
        uint256 amount
    );

    /// @notice Emitted when a user deposits `amount of `yieldToken` to `recipient`.
    ///
    /// @notice This event does not imply that `sender` directly deposited yield tokens. It is possible that the
    ///         base tokens were wrapped.
    ///
    /// @param sender       The address of the user which deposited funds.
    /// @param yieldToken   The address of the yield token that was deposited.
    /// @param amount       The amount of yield tokens that were deposited.
    /// @param recipient    The address that received the deposited funds.
    event DepositYieldToken(
        address indexed sender,
        address indexed yieldToken,
        uint256 amount,
        address recipient
    );

    /// @notice Emitted when `shares` shares of `yieldToken` are burned to withdraw `yieldToken` from the account owned
    ///         by `owner` to `recipient`.
    ///
    /// @notice This event does not imply that `recipient` received yield tokens. It is possible that the yield tokens
    ///         were unwrapped.
    ///
    /// @param owner      The address of the account owner.
    /// @param yieldToken The address of the yield token that was withdrawn.
    /// @param shares     The amount of shares that were burned.
    /// @param recipient  The address that received the withdrawn funds.
    event WithdrawYieldToken(
        address indexed owner,
        address indexed yieldToken,
        uint256 shares,
        address recipient
    );

    /// @notice Emitted when `amount` debt tokens are borrowed to `recipient` using the account owned by `owner`.
    ///
    /// @param owner     The address of the account owner.
    /// @param amount    The amount of tokens that were borrowed.
    /// @param recipient The recipient of the borrowed tokens.
    event Borrow(address indexed owner, uint256 amount, address recipient);

    /// @notice Emitted when `sender` burns `amount` debt tokens to grant credit to `recipient`.
    ///
    /// @param sender    The address which is burning tokens.
    /// @param amount    The amount of tokens that were burned.
    /// @param recipient The address that received credit for the burned tokens.
    event RepayWithDebtToken(
        address indexed sender,
        uint256 amount,
        address recipient
    );

    /// @notice Emitted when `amount` of `baseToken` are repaid to grant credit to `recipient`.
    ///
    /// @param sender          The address which is repaying tokens.
    /// @param baseToken The address of the base token that was used to repay debt.
    /// @param amount          The amount of the base token that was used to repay debt.
    /// @param recipient       The address that received credit for the repaid tokens.
    /// @param credit          The amount of debt that was paid-off to the account owned by owner.
    event RepayWithBaseToken(
        address indexed sender,
        address indexed baseToken,
        uint256 amount,
        address recipient,
        uint256 credit
    );

    /// @notice Emitted when `sender` repayWithCollateral `share` shares of `yieldToken`.
    ///
    /// @param owner           The address of the account owner repaying with collateral.
    /// @param yieldToken      The address of the yield token.
    /// @param baseToken The address of the base token.
    /// @param shares          The amount of the shares of `yieldToken` that were repaidWithCollateral.
    /// @param credit          The amount of debt that was paid-off to the account owned by owner.
    event RepayWithCollateral(
        address indexed owner,
        address indexed yieldToken,
        address indexed baseToken,
        uint256 shares,
        uint256 credit
    );

    /// @notice Emitted when `sender` burns `amount` debt tokens to grant credit to users who have deposited `yieldToken`.
    ///
    /// @param sender     The address which burned debt tokens.
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of debt tokens which were burned.
    event Donate(
        address indexed sender,
        address indexed yieldToken,
        uint256 amount
    );

    /// @notice Emitted when `yieldToken` is harvested.
    ///
    /// @param yieldToken     The address of the yield token that was harvested.
    /// @param minimumAmountOut    The maximum amount of loss that is acceptable when unwrapping the base tokens into yield tokens, measured in basis points.
    /// @param totalHarvested The total amount of base tokens harvested.
    /// @param credit           The total amount of debt repaid to depositors of `yieldToken`.
    event Harvest(
        address indexed yieldToken,
        uint256 minimumAmountOut,
        uint256 totalHarvested,
        uint256 credit
    );

    /// @notice Emitted when the offset as baseToken exceeds to limit.
    ///
    /// @param yieldToken      The address of the yield token that was harvested.
    /// @param currentValue    Current value as baseToken.
    /// @param expectedValue   Limit offset value.
    event HarvestExceedsOffset(
        address indexed yieldToken,
        uint256 currentValue,
        uint256 expectedValue
    );
}

