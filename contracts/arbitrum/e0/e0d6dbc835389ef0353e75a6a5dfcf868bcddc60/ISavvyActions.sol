// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  ISavvyActions
/// @author Savvy DeFi
///
/// @notice Specifies user actions.
interface ISavvyActions {
    /// @notice Approve `spender` to borrow `amount` debt tokens.
    ///
    /// **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @param spender The address that will be approved to borrow.
    /// @param amount  The amount of tokens that `spender` will be allowed to borrow.
    function approveBorrow(address spender, uint256 amount) external;

    /// @notice Approve `spender` to withdraw `amount` shares of `yieldToken`.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @param spender    The address that will be approved to withdraw.
    /// @param yieldToken The address of the yield token that `spender` will be allowed to withdraw.
    /// @param shares     The amount of shares that `spender` will be allowed to withdraw.
    function approveWithdraw(
        address spender,
        address yieldToken,
        uint256 shares
    ) external;

    /// @notice Synchronizes the state of the account owned by `owner`.
    ///
    /// @param owner The owner of the account to synchronize.
    function syncAccount(address owner) external;

    /// @notice Deposit an base token into the account of `recipient` as `yieldToken`.
    ///
    /// @notice An approval must be set for the base token of `yieldToken` which is greater than `amount`.
    ///
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    /// @notice `amount` must be greater than zero or the call will revert with an {IllegalArgument} error.
    ///
    /// @notice Emits a {Deposit} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    /// @notice **_NOTE:_** When depositing, the `SavvyPositionManager` contract must have **allowance()** to spend funds on behalf of **msg.sender** for at least **amount** of the **baseToken** being deposited.  This can be done via the standard `ERC20.approve()` method.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address mooAaveDAI = 0xAf9f33df60CA764307B17E62dde86e9F7090426c;
    /// @notice uint256 amount = 50000;
    /// @notice SavvyPositionManager(savvyAddress).depositBaseToken(mooAaveDAI, amount, msg.sender, 1);
    /// @notice ```
    ///
    /// @param yieldToken       The address of the yield token to wrap the base tokens into.
    /// @param amount           The amount of the base token to deposit.
    /// @param recipient        The address of the recipient.
    /// @param minimumAmountOut The minimum amount of yield tokens that are expected to be deposited to `recipient`.
    ///
    /// @return sharesIssued The number of shares issued to `recipient`.
    function depositBaseToken(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) external returns (uint256 sharesIssued);

    /// @notice Deposit a yield token into a user's account.
    ///
    /// @notice An approval must be set for `yieldToken` which is greater than `amount`.
    ///
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice `yieldToken` must be enabled or this call will revert with a {TokenDisabled} error.
    /// @notice `yieldToken` base token must be enabled or this call will revert with a {TokenDisabled} error.
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    /// @notice `amount` must be greater than zero or the call will revert with an {IllegalArgument} error.
    ///
    /// @notice Emits a {Deposit} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @notice **_NOTE:_** When depositing, the `SavvyPositionManager` contract must have **allowance()** to spend funds on behalf of **msg.sender** for at least **amount** of the **yieldToken** being deposited.  This can be done via the standard `ERC20.approve()` method.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address mooAaveDAI = 0xAf9f33df60CA764307B17E62dde86e9F7090426c;
    /// @notice uint256 amount = 50000;
    /// @notice IERC20(mooAaveDAI).approve(savvyAddress, amount);
    /// @notice SavvyPositionManager(savvyAddress).depositYieldToken(mooAaveDAI, amount, msg.sender);
    /// @notice ```
    ///
    /// @param yieldToken The yield-token to deposit.
    /// @param amount     The amount of yield tokens to deposit.
    /// @param recipient  The owner of the account that will receive the resulting shares.
    ///
    /// @return sharesIssued The number of shares issued to `recipient`.
    function depositYieldToken(
        address yieldToken,
        uint256 amount,
        address recipient
    ) external returns (uint256 sharesIssued);

    /// @notice Withdraw amount yield tokens to recipient The number of yield tokens withdrawn to `recipient` will depend on the value of shares for that yield token at the time of the call.
    ///
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    ///
    /// @notice Emits a {Withdraw} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address mooAaveDAI = 0xAf9f33df60CA764307B17E62dde86e9F7090426c;
    /// @notice uint256 pps = SavvyPositionManager(savvyAddress).getYieldTokensPerShare(mooAaveDAI);
    /// @notice uint256 amtYieldTokens = 5000;
    /// @notice SavvyPositionManager(savvyAddress).withdrawYieldToken(mooAaveDAI, amtYieldTokens / pps, msg.sender);
    /// @notice ```
    ///
    /// @param yieldToken The address of the yield token to withdraw.
    /// @param shares     The number of shares to burn.
    /// @param recipient  The address of the recipient.
    ///
    /// @return amountWithdrawn The number of yield tokens that were withdrawn to `recipient`.
    function withdrawYieldToken(
        address yieldToken,
        uint256 shares,
        address recipient
    ) external returns (uint256 amountWithdrawn);

    /// @notice Withdraw yield tokens to `recipient` by burning `share` shares from the account of `owner`
    ///
    /// @notice `owner` must have an withdrawal allowance which is greater than `amount` for this call to succeed.
    ///
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    ///
    /// @notice Emits a {Withdraw} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address mooAaveDAI = 0xAf9f33df60CA764307B17E62dde86e9F7090426c;
    /// @notice uint256 pps = SavvyPositionManager(savvyAddress).getYieldTokensPerShare(mooAaveDAI);
    /// @notice uint256 amtYieldTokens = 5000;
    /// @notice SavvyPositionManager(savvyAddress).withdrawFrom(msg.sender, mooAaveDAI, amtYieldTokens / pps, msg.sender);
    /// @notice ```
    ///
    /// @param owner      The address of the account owner to withdraw from.
    /// @param yieldToken The address of the yield token to withdraw.
    /// @param shares     The number of shares to burn.
    /// @param recipient  The address of the recipient.
    ///
    /// @return amountWithdrawn The number of yield tokens that were withdrawn to `recipient`.
    function withdrawYieldTokenFrom(
        address owner,
        address yieldToken,
        uint256 shares,
        address recipient
    ) external returns (uint256 amountWithdrawn);

    /// @notice Withdraw base tokens to `recipient` by burning `share` shares and unwrapping the yield tokens that the shares were redeemed for.
    ///
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    /// @notice The loss in expected value of `yieldToken` must be less than the maximum permitted by the system or this call will revert with a {LossExceeded} error.
    ///
    /// @notice Emits a {Withdraw} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    /// @notice **_NOTE:_** The caller of `withdrawYieldTokenFrom()` must have **withdrawAllowance()** to withdraw funds on behalf of **owner** for at least the amount of `yieldTokens` that **shares** will be converted to.  This can be done via the `approveWithdraw()` or `permitWithdraw()` methods.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address mooAaveDAI = 0xAf9f33df60CA764307B17E62dde86e9F7090426c;
    /// @notice uint256 pps = SavvyPositionManager(savvyAddress).getBaseTokensPerShare(mooAaveDAI);
    /// @notice uint256 amountBaseTokens = 5000;
    /// @notice SavvyPositionManager(savvyAddress).withdrawUnderlying(mooAaveDAI, amountBaseTokens / pps, msg.sender, 1);
    /// @notice ```
    ///
    /// @param yieldToken       The address of the yield token to withdraw.
    /// @param shares           The number of shares to burn.
    /// @param recipient        The address of the recipient.
    /// @param minimumAmountOut The minimum amount of base tokens that are expected to be withdrawn to `recipient`.
    ///
    /// @return amountWithdrawn The number of base tokens that were withdrawn to `recipient`.
    function withdrawBaseToken(
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) external returns (uint256 amountWithdrawn);

    /// @notice Withdraw base tokens to `recipient` by burning `share` shares from the account of `owner` and unwrapping the yield tokens that the shares were redeemed for.
    ///
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    /// @notice The loss in expected value of `yieldToken` must be less than the maximum permitted by the system or this call will revert with a {LossExceeded} error.
    ///
    /// @notice Emits a {Withdraw} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    /// @notice **_NOTE:_** The caller of `withdrawYieldTokenFrom()` must have **withdrawAllowance()** to withdraw funds on behalf of **owner** for at least the amount of `yieldTokens` that **shares** will be converted to.  This can be done via the `approveWithdraw()` or `permitWithdraw()` methods.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address mooAaveDAI = 0xAf9f33df60CA764307B17E62dde86e9F7090426c;
    /// @notice uint256 pps = SavvyPositionManager(savvyAddress).getBaseTokensPerShare(mooAaveDAI);
    /// @notice uint256 amtBaseTokens = 5000 * 10**mooAaveDAI.decimals();
    /// @notice SavvyPositionManager(savvyAddress).withdrawUnderlying(msg.sender, mooAaveDAI, amtBaseTokens / pps, msg.sender, 1);
    /// @notice ```
    ///
    /// @param owner            The address of the account owner to withdraw from.
    /// @param yieldToken       The address of the yield token to withdraw.
    /// @param shares           The number of shares to burn.
    /// @param recipient        The address of the recipient.
    /// @param minimumAmountOut The minimum amount of base tokens that are expected to be withdrawn to `recipient`.
    ///
    /// @return amountWithdrawn The number of base tokens that were withdrawn to `recipient`.
    function withdrawBaseTokenFrom(
        address owner,
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) external returns (uint256 amountWithdrawn);

    /// @notice borrow `amount` debt tokens to recipient.
    ///
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    /// @notice `amount` must be greater than zero or this call will revert with a {IllegalArgument} error.
    ///
    /// @notice Emits a {Borrow} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice uint256 amtDebt = 5000;
    /// @notice SavvyPositionManager(savvyAddress).borrowCredit(amtDebt, msg.sender);
    /// @notice ```
    ///
    /// @param amount    The amount of tokens to borrow.
    /// @param recipient The address of the recipient.
    function borrowCredit(uint256 amount, address recipient) external;

    /// @notice Borrow `amount` debt tokens from the account owned by `owner` to `recipient`.
    ///
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    /// @notice `amount` must be greater than zero or this call will revert with a {IllegalArgument} error.
    ///
    /// @notice Emits a {Borrow} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    /// @notice **_NOTE:_** The caller of `borrowFrom()` must have **borrowAllowance()** to borrow debt from the `Account` controlled by **owner** for at least the amount of **yieldTokens** that **shares** will be converted to.  This can be done via the `approveBorrow()` or `permitBorrow()` methods.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice uint256 amtDebt = 5000;
    /// @notice SavvyPositionManager(savvyAddress).borrowFrom(msg.sender, amtDebt, msg.sender);
    /// @notice ```
    ///
    /// @param owner     The address of the owner of the account to borrow from.
    /// @param amount    The amount of tokens to borrow.
    /// @param recipient The address of the recipient.
    function borrowCreditFrom(
        address owner,
        uint256 amount,
        address recipient
    ) external;

    /// @notice Burn `amount` debt tokens to credit the account owned by `recipient`.
    ///
    /// @notice `amount` will be limited up to the amount of debt that `recipient` currently holds.
    ///
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    /// @notice `amount` must be greater than zero or this call will revert with a {IllegalArgument} error.
    /// @notice `recipient` must have non-zero debt or this call will revert with an {IllegalState} error.
    ///
    /// @notice Emits a {Burn} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice uint256 amtBurn = 5000;
    /// @notice SavvyPositionManager(savvyAddress).repayWithDebtToken(amtBurn, msg.sender);
    /// @notice ```
    ///
    /// @param amount    The amount of tokens to burn.
    /// @param recipient The address of the recipient.
    ///
    /// @return amountBurned The amount of tokens that were burned.
    function repayWithDebtToken(
        uint256 amount,
        address recipient
    ) external returns (uint256 amountBurned);

    /// @notice Repay `amount` debt using `baseToken` to credit the account owned by `recipient`.
    ///
    /// @notice `amount` will be limited up to the amount of debt that `recipient` currently holds.
    ///
    /// @notice `amount` must be greater than zero or this call will revert with a {IllegalArgument} error.
    /// @notice `recipient` must be non-zero or this call will revert with an {IllegalArgument} error.
    /// @notice `baseToken` must be enabled or this call will revert with a {TokenDisabled} error.
    /// @notice `amount` must be less than or equal to the current available repay limit or this call will revert with a {ReplayLimitExceeded} error.
    ///
    /// @notice Emits a {Repay} event.
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address dai = 0x6b175474e89094c44da98b954eedeac495271d0f;
    /// @notice uint256 amtRepay = 5000;
    /// @notice SavvyPositionManager(savvyAddress).repayWithBaseToken(dai, amtRepay, msg.sender);
    /// @notice ```
    ///
    /// @param baseToken The address of the base token to repay.
    /// @param amount          The amount of the base token to repay.
    /// @param recipient       The address of the recipient which will receive credit.
    ///
    /// @return amountRepaid The amount of tokens that were repaid.
    function repayWithBaseToken(
        address baseToken,
        uint256 amount,
        address recipient
    ) external returns (uint256 amountRepaid);

    /// @notice
    ///
    /// @notice `shares` will be limited up to an equal amount of debt that `recipient` currently holds.
    ///
    /// @notice `shares` must be greater than zero or this call will revert with a {IllegalArgument} error.
    /// @notice `yieldToken` must be registered or this call will revert with a {UnsupportedToken} error.
    /// @notice `yieldToken` must be enabled or this call will revert with a {TokenDisabled} error.
    /// @notice `yieldToken` base token must be enabled or this call will revert with a {TokenDisabled} error.
    /// @notice The loss in expected value of `yieldToken` must be less than the maximum permitted by the system or this call will revert with a {LossExceeded} error.
    /// @notice `amount` must be less than or equal to the current available repayWithCollateral limit or this call will revert with a {RepayWithCollateralLimitExceeded} error.
    ///
    /// @notice Emits a {RepayWithCollateral} event.
    ///
    /// @notice **_NOTE:_** This function is ALLOWLISTED.
    ///
    /// @notice **Example:**
    /// @notice ```
    /// @notice address mooAaveDAI = 0xAf9f33df60CA764307B17E62dde86e9F7090426c;
    /// @notice uint256 amtRepayWithCollateral = 5000 * 10**mooAaveDAI.decimals();
    /// @notice SavvyPositionManager(savvyAddress).repayWithCollateral(mooAaveDAI, amtRepayWithCollateral, 1);
    /// @notice ```
    ///
    /// @param yieldToken       The address of the yield token to repayWithCollateral.
    /// @param shares           The number of shares to burn for credit.
    /// @param minimumAmountOut The minimum amount of base tokens that are expected to be repaidWithCollateral.
    ///
    /// @return sharesRepaidWithCollateral The amount of shares that were repaidWithCollateral.
    function repayWithCollateral(
        address yieldToken,
        uint256 shares,
        uint256 minimumAmountOut
    ) external returns (uint256 sharesRepaidWithCollateral);

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
    function donate(address yieldToken, uint256 amount) external;

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
    function harvest(address yieldToken, uint256 minimumAmountOut) external;
}

