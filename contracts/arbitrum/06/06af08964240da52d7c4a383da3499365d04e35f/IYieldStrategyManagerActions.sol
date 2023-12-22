// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./Limiters.sol";
import "./ISavvyAdminActions.sol";
import "./ISavvyTokenParams.sol";

/// @title  IYieldStrategyManagerActions
/// @author Savvy DeFi
interface IYieldStrategyManagerActions is ISavvyTokenParams {
    /// @dev Unwraps `amount` of `yieldToken` into its base token.
    ///
    /// @param yieldToken       The address of the yield token to unwrap.
    /// @param amount           The amount of the yield token to wrap.
    /// @param minimumAmountOut The minimum amount of base tokens that are expected to be received from the
    ///                         operation.
    ///
    /// @return The amount of base tokens that resulted from the operation.
    function unwrap(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) external returns (uint256);

    /// @notice Burns `amount` debt tokens to credit accounts which have deposited `yieldToken`.
    ///
    /// @notice `amount` must be greater than zero or this call will revert with a {IllegalArgument} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @notice Emits a {Donate} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address mooAaveDAI = 0xAf9f33df60CA764307B17E62dde86e9F7090426c;
    /// @notice uint256 amtRepayWithCollateral = 5000;
    /// @notice SavvyPositionManager(savvyAddress).repayWithCollateral(dai, amtRepayWithCollateral, 1);
    /// @notice ```
    ///
    /// @param yieldToken The address of the yield token to credit accounts for.
    /// @param amount     The amount of debt tokens to burn.
    /// @param shares     The amount of share left in savvy.
    function donate(
        address yieldToken,
        uint256 amount,
        uint256 shares
    ) external returns (uint256);

    /// @notice Harvests outstanding yield that a yield token has accumulated and distributes it as credit to holders.
    ///
    /// @notice `msg.sender` must be a keeper or this call will revert with an {Unauthorized} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice The amount being harvested must be greater than zero or else this call will revert with an {IllegalState} error.
    ///
    /// @notice Emits a {Harvest} event.
    ///
    /// @param yieldToken       The address of the yield token to harvest.
    /// @param minimumAmountOut The minimum amount of base tokens that are expected to be withdrawn to `recipient`.
    /// @param protocolFee      The rate of protocol fee.
    /// @return baseToken           The address of base token.
    /// @return amountBaseTokens    The amount of base token.
    /// @return feeAmount           The amount of protocol fee.
    /// @return distributeAmount    The amount of distribute
    /// @return credit              The amount of debt.
    function harvest(
        address yieldToken,
        uint256 minimumAmountOut,
        uint256 protocolFee
    )
        external
        returns (
            address baseToken,
            uint256 amountBaseTokens,
            uint256 feeAmount,
            uint256 distributeAmount,
            uint256 credit
        );

    /// @notice Synchronizes the active balance and expected value of `yieldToken`.
    /// @param yieldToken       The address of yield token.
    /// @param amount           The amount to add or subtract from the debt.
    /// @param addOperation     Present for add or sub.
    /// @return                 The config of yield token.
    function syncYieldToken(
        address yieldToken,
        uint256 amount,
        bool addOperation
    ) external returns (YieldTokenParams memory);

    /// @dev Burns `share` shares of `yieldToken` from the account owned by `owner`.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param shares     The amount of shares to burn.
    function burnShares(address yieldToken, uint256 shares) external;

    /// @dev Issues shares of `yieldToken` for `amount` of its base token to `recipient`.
    ///
    /// IMPORTANT: `amount` must never be 0.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of yield token.
    /// @return shares    The amount of shars.
    function issueSharesForAmount(
        address yieldToken,
        uint256 amount
    ) external returns (uint256 shares);

    /// @notice Update repay limiters and returns debt amount and actual amount of base token.
    /// @param baseToken The address of base token.
    /// @return Return debt amount same worth as `amount` of base token.
    /// @return Return actual amount of base token for repay debt.
    function repayWithBaseToken(
        address baseToken,
        uint256 amount,
        int256 debt
    ) external view returns (uint256, uint256);

    /// @notice Check if had condition to do repayWithCollateral.
    /// @notice checkSupportedYieldToken(), checkTokenEnabled(), checkLoss()
    /// @param yieldToken The address of yield token.
    /// @return baseToken The address of base token.
    function repayWithCollateralCheck(
        address yieldToken
    ) external view returns (address baseToken);

    /// @dev Distributes unlocked credit of `yieldToken` to all depositors.
    ///
    /// @param yieldToken The address of the yield token to distribute unlocked credit for.
    function distributeUnlockedCredit(address yieldToken) external;

    /// @dev Preemptively harvests `yieldToken`.
    ///
    /// @dev This will earmark yield tokens to be harvested at a future time when the current value of the token is
    ///      greater than the expected value. The purpose of this function is to synchronize the balance of the yield
    ///      token which is held by users versus tokens which will be seized by the protocol.
    ///
    /// @param yieldToken The address of the yield token to preemptively harvest.
    function preemptivelyHarvest(address yieldToken) external;

    /// @notice Snap the expected value `yieldToken` to the current value.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    ///
    /// @dev This function should only be used in the event of a loss in the target yield-token. For example, say a third-party protocol experiences a fifty percent loss. The expected value (amount of base tokens) of the yield tokens being held by the system would be two times the real value that those yield tokens could be redeemed for. This function gives governance a way to realize those losses so that users can continue using the token as normal.
    ///
    /// @param yieldToken The address of the yield token to snap.
    function snap(address yieldToken) external returns (uint256);

    /// @notice Do pre actions for deposit.
    /// @notice checkTokenEnabled(), checkLoss(), preemptivelyHarvest()
    /// @param yieldToken The address of yield token.
    /// @return yieldTokenParam The config of yield token.
    function depositPrepare(
        address yieldToken
    )
        external
        returns (YieldTokenParams memory yieldTokenParam);

    /// @notice `shares` will be limited up to an equal amount of debt that `recipient` currently holds.
    /// @dev Explain to a developer any extra details
    /// @param yieldToken       The address of the yield token to repayWithCollateral.
    /// @param recipient        The address of user that will derease debt.
    /// @param shares           The number of shares to burn for credit.
    /// @param minimumAmountOut The minimum amount of base tokens that are expected to be repaidWithCollateral.
    /// @param unrealizedDebt   The amount of the debt unrealized.
    /// @return The amount of base token.
    /// @return The amount of yield token.
    /// @return The amount of shares that used actually to decrease debt.
    function repayWithCollateral(
        address yieldToken,
        address recipient,
        uint256 shares,
        uint256 minimumAmountOut,
        int256 unrealizedDebt
    ) external returns (uint256, uint256, uint256);
}

