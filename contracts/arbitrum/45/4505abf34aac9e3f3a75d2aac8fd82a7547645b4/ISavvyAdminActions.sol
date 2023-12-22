// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  ISavvyAdminActions
/// @author Savvy DeFi
///
/// @notice Specifies admin and/or sentinel actions.
/// @notice Used by SavvyPositionManager
interface ISavvyAdminActions {
    /// @notice Contract initialization parameters.
    struct InitializationParams {
        // The initial admin account.
        address admin;
        // The ERC20 token used to represent debt.
        address debtToken;
        // The initial savvySage or savvySage buffer.
        address savvySage;
        // The address of giving rewards to users.
        address svyBooster;
        // The address of SavvyPriceFeed contract.
        address svyPriceFeed;
        // The redlist is active.
        bool redlistActive;
        // The address of Redlist contract.
        address savvyRedlist;
        // The address of YieldStrategyManager contract.
        address yieldStrategyManager;
        // The minimum collateralization ratio that an account must maintain.
        uint256 minimumCollateralization;
        // The percentage fee taken from each harvest measured in units of basis points.
        uint256 protocolFee;
        // The address that receives protocol fees.
        address protocolFeeReceiver;
        // A limit used to prevent administrators from making borrowing functionality inoperable.
        uint256 borrowingLimitMinimum;
        // The maximum number of tokens that can be borrowed per period of time.
        uint256 borrowingLimitMaximum;
        // The number of blocks that it takes for the borrowing limit to be refreshed.
        uint256 borrowingLimitBlocks;
        // The address of the allowlist.
        address allowlist;
        // Base base token to calculate token price.
        address baseToken;
        /// The address of WrapTokenGateway contract.
        address wrapTokenGateway;
    }

    /// @notice Configuration parameters for an base token.
    struct BaseTokenConfig {
        // A limit used to prevent administrators from making repayment functionality inoperable.
        uint256 repayLimitMinimum;
        // The maximum number of base tokens that can be repaid per period of time.
        uint256 repayLimitMaximum;
        // The number of blocks that it takes for the repayment limit to be refreshed.
        uint256 repayLimitBlocks;
        // A limit used to prevent administrators from making repayWithCollateral functionality inoperable.
        uint256 repayWithCollateralLimitMinimum;
        // The maximum number of base tokens that can be repaidWithCollateral per period of time.
        uint256 repayWithCollateralLimitMaximum;
        // The number of blocks that it takes for the repayWithCollateral limit to be refreshed.
        uint256 repayWithCollateralLimitBlocks;
    }

    /// @notice Configuration parameters of a yield token.
    struct YieldTokenConfig {
        // The adapter used by the system to interop with the token.
        address adapter;
        // The maximum percent loss in expected value that can occur before certain actions are disabled.
        // Measured in units of basis points.
        uint256 maximumLoss;
        // The maximum value that can be held by the system before certain actions are disabled.
        //  measured in the base token.
        uint256 maximumExpectedValue;
        // The number of blocks that credit will be distributed over to depositors.
        uint256 creditUnlockBlocks;
    }

    /// @notice Initialize the contract.
    ///
    /// @notice `params.protocolFee` must be in range or this call will with an {IllegalArgument} error.
    /// @notice The borrowing growth limiter parameters must be valid or this will revert with an {IllegalArgument} error. For more information, see the {Limiters} library.
    ///
    /// @notice Emits an {AdminUpdated} event.
    /// @notice Emits a {SavvySageUpdated} event.
    /// @notice Emits a {MinimumCollateralizationUpdated} event.
    /// @notice Emits a {ProtocolFeeUpdated} event.
    /// @notice Emits a {ProtocolFeeReceiverUpdated} event.
    /// @notice Emits a {BorrowingLimitUpdated} event.
    ///
    /// @param params The contract initialization parameters.
    function initialize(InitializationParams calldata params) external;

    /// @notice Sets the pending administrator.
    ///
    /// @notice `msg.sender` must be the pending admin or this call will revert with an {Unauthorized} error.
    ///
    /// @notice Emits a {PendingAdminUpdated} event.
    ///
    /// @dev This is the first step in the two-step process of setting a new administrator. After this function is called, the pending administrator will then need to call {acceptAdmin} to complete the process.
    ///
    /// @param value the address to set the pending admin to.
    function setPendingAdmin(address value) external;

    /// @notice Allows for `msg.sender` to accepts the role of administrator.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice The current pending administrator must be non-zero or this call will revert with an {IllegalState} error.
    ///
    /// @dev This is the second step in the two-step process of setting a new administrator. After this function is successfully called, this pending administrator will be reset and the new administrator will be set.
    ///
    /// @notice Emits a {AdminUpdated} event.
    /// @notice Emits a {PendingAdminUpdated} event.
    function acceptAdmin() external;

    /// @notice Sets an address as a sentinel.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    ///
    /// @param sentinel The address to set or unset as a sentinel.
    /// @param flag     A flag indicating of the address should be set or unset as a sentinel.
    function setSentinel(address sentinel, bool flag) external;

    /// @notice Sets an address as a keeper.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    ///
    /// @param keeper The address to set or unset as a keeper.
    /// @param flag   A flag indicating of the address should be set or unset as a keeper.
    function setKeeper(address keeper, bool flag) external;

    /// @notice Adds an base token to the system.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    ///
    /// @param baseToken The address of the base token to add.
    /// @param config          The initial base token configuration.
    function addBaseToken(
        address baseToken,
        BaseTokenConfig calldata config
    ) external;

    /// @notice Adds a yield token to the system.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    ///
    /// @notice Emits a {AddYieldToken} event.
    /// @notice Emits a {TokenAdapterUpdated} event.
    /// @notice Emits a {MaximumLossUpdated} event.
    ///
    /// @param yieldToken The address of the yield token to add.
    /// @param config     The initial yield token configuration.
    function addYieldToken(
        address yieldToken,
        YieldTokenConfig calldata config
    ) external;

    /// @notice Sets an base token as either enabled or disabled.
    ///
    /// @notice `msg.sender` must be either the admin or a sentinel or this call will revert with an {Unauthorized} error.
    /// @notice `baseToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @notice Emits an {BaseTokenEnabled} event.
    ///
    /// @param baseToken The address of the base token to enable or disable.
    /// @param enabled         If the base token should be enabled or disabled.
    function setBaseTokenEnabled(address baseToken, bool enabled) external;

    /// @notice Sets a yield token as either enabled or disabled.
    ///
    /// @notice `msg.sender` must be either the admin or a sentinel or this call will revert with an {Unauthorized} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @notice Emits a {YieldTokenEnabled} event.
    ///
    /// @param yieldToken The address of the yield token to enable or disable.
    /// @param enabled    If the base token should be enabled or disabled.
    function setYieldTokenEnabled(address yieldToken, bool enabled) external;

    /// @notice Configures the the repay limit of `baseToken`.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `baseToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @notice Emits a {ReplayLimitUpdated} event.
    ///
    /// @param baseToken The address of the base token to configure the repay limit of.
    /// @param maximum         The maximum repay limit.
    /// @param blocks          The number of blocks it will take for the maximum repayment limit to be replenished when it is completely exhausted.
    function configureRepayLimit(
        address baseToken,
        uint256 maximum,
        uint256 blocks
    ) external;

    /// @notice Configure the repayWithCollateral limiter of `baseToken`.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `baseToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @notice Emits a {RepayWithCollateralLimitUpdated} event.
    ///
    /// @param baseToken The address of the base token to configure the repayWithCollateral limit of.
    /// @param maximum         The maximum repayWithCollateral limit.
    /// @param blocks          The number of blocks it will take for the maximum repayWithCollateral limit to be replenished when it is completely exhausted.
    function configureRepayWithCollateralLimit(
        address baseToken,
        uint256 maximum,
        uint256 blocks
    ) external;

    /// @notice Set the address of the savvySage.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `value` must be non-zero or this call will revert with an {IllegalArgument} error.
    ///
    /// @notice Emits a {SavvySageUpdated} event.
    ///
    /// @param savvySage The address of the savvySage.
    function setSavvySage(address savvySage) external;

    /// @notice Set the minimum collateralization ratio.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    ///
    /// @notice Emits a {MinimumCollateralizationUpdated} event.
    ///
    /// @param value The new minimum collateralization ratio.
    function setMinimumCollateralization(uint256 value) external;

    /// @notice Sets the fee that the protocol will take from harvests.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `value` must be in range or this call will with an {IllegalArgument} error.
    ///
    /// @notice Emits a {ProtocolFeeUpdated} event.
    ///
    /// @param value The value to set the protocol fee to measured in basis points.
    function setProtocolFee(uint256 value) external;

    /// @notice Sets the address which will receive protocol fees.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `value` must be non-zero or this call will revert with an {IllegalArgument} error.
    ///
    /// @notice Emits a {ProtocolFeeReceiverUpdated} event.
    ///
    /// @param value The address to set the protocol fee receiver to.
    function setProtocolFeeReceiver(address value) external;

    /// @notice Configures the borrowing limiter.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    ///
    /// @notice Emits a {BorrowingLimitUpdated} event.
    ///
    /// @param maximum The maximum borrowing limit.
    /// @param blocks  The number of blocks it will take for the maximum borrowing limit to be replenished when it is completely exhausted.
    function configureBorrowingLimit(uint256 maximum, uint256 blocks) external;

    /// @notice Sets the rate at which credit will be completely available to depositors after it is harvested.
    ///
    /// @notice Emits a {CreditUnlockRateUpdated} event.
    ///
    /// @param yieldToken The address of the yield token to set the credit unlock rate for.
    /// @param blocks     The number of blocks that it will take before the credit will be unlocked.
    function configureCreditUnlockRate(
        address yieldToken,
        uint256 blocks
    ) external;

    /// @notice Sets the token adapter of a yield token.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice The token that `adapter` supports must be `yieldToken` or this call will revert with a {IllegalState} error.
    ///
    /// @notice Emits a {TokenAdapterUpdated} event.
    ///
    /// @param yieldToken The address of the yield token to set the adapter for.
    /// @param adapter    The address to set the token adapter to.
    function setTokenAdapter(address yieldToken, address adapter) external;

    /// @notice Sets the maximum expected value of a yield token that the system can hold.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @param yieldToken The address of the yield token to set the maximum expected value for.
    /// @param value      The maximum expected value of the yield token denoted measured in its base token.
    function setMaximumExpectedValue(
        address yieldToken,
        uint256 value
    ) external;

    /// @notice Sets the maximum loss that a yield bearing token will permit before restricting certain actions.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @dev There are two types of loss of value for yield bearing tokens: temporary or permanent. The system will automatically restrict actions which are sensitive to both forms of loss when detected. For example, deposits must be restricted when an excessive loss is encountered to prevent users from having their collateral harvested from them. While the user would receive credit, which then could be exchanged for value equal to the collateral that was harvested from them, it is seen as a negative user experience because the value of their collateral should have been higher than what was originally recorded when they made their deposit.
    ///
    /// @param yieldToken The address of the yield bearing token to set the maximum loss for.
    /// @param value      The value to set the maximum loss to. This is in units of basis points.
    function setMaximumLoss(address yieldToken, uint256 value) external;

    /// @notice Snap the expected value `yieldToken` to the current value.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @dev This function should only be used in the event of a loss in the target yield-token. For example, say a third-party protocol experiences a fifty percent loss. The expected value (amount of base tokens) of the yield tokens being held by the system would be two times the real value that those yield tokens could be redeemed for. This function gives governance a way to realize those losses so that users can continue using the token as normal.
    ///
    /// @param yieldToken The address of the yield token to snap.
    function snap(address yieldToken) external;

    /// @notice Sweep all of 'rewardtoken' from the savvy into the admin.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `rewardToken` must not be a yield or base token or this call will revert with a {UnsupportedToken} error.
    ///
    /// @param rewardToken The address of the reward token to snap.
    /// @param amount The amount of 'rewardToken' to sweep to the admin.
    function sweepTokens(address rewardToken, uint256 amount) external;
}

