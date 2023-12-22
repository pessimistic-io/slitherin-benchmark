// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.7;

// TODO interface copy needs some further edits to reflect new implementation

/// @notice Enforces deposit caps.
interface IDepositRecord {
  /**
   * @dev Emitted via `setGlobalNetDepositCap()`.
   * @param cap New global deposit cap (net of withdrawals)
   */
  event GlobalNetDepositCapChange(uint256 cap);

  /**
   * @dev Emitted via `setUserDepositCap()`.
   * @param cap New user deposit cap
   */
  event UserDepositCapChange(uint256 cap);

  /**
   * @dev This function will be called by a hook before the fee
   * is subtracted from the initial `amount` passed in.
   *
   * Only callable by allowed hooks.
   *
   * Reverts if the incoming deposit brings either total over their
   * respective caps.
   *
   * `amount` is added to both the global and user-specific
   * deposit totals.
   * @param sender The account making the deposit
   * @param amount The amount actually deposited by the user
   */
  function recordDeposit(address sender, uint256 amount) external;

  /**
   * @notice Called by a hook before the fee is subtracted from
   * the amount withdrawn from the Strategy.
   * @dev `amount` is subtracted from the global but not
   * user-specific deposit totals.
   *
   * Only callable by allowed hooks.
   * @param amount The amount actually withdrawn by the user
   */
  function recordWithdrawal(uint256 amount) external;

  /**
   * @notice Sets the global net deposit cap.
   * @dev Only callable by owner().
   * @param globalNetDepositCap The new global net deposit cap
   */
  function setGlobalNetDepositCap(uint256 globalNetDepositCap) external;

  /**
   * @notice Sets the cap on Base Token deposits per user. User deposit caps
   * are not calculated in a net fashion, unlike global caps.
   * @dev Only callable by owner().
   * @param userDepositCap The new account deposit cap
   */
  function setUserDepositCap(uint256 userDepositCap) external;

  /**
   * @notice Gets the maximum Base Token amount that is allowed to be
   * deposited (net of withdrawals).
   * @dev Deposits are not allowed if `globalNetDepositAmount` exceeds
   * the `globalNetDepositCap`.
   * @return The cap on global Base Token deposits (net of withdrawals)
   */
  function getGlobalNetDepositCap() external view returns (uint256);

  /// @return Net total of Base Token deposited.
  function getGlobalNetDepositAmount() external view returns (uint256);

  /**
   * @notice Gets the maximum Base Token amount that a user can deposit, not
   * including withdrawals.
   * @return The cap on Base Token deposits per user
   */
  function getUserDepositCap() external view returns (uint256);

  /**
   * @param account The account to retrieve total deposits for
   * @return The total amount of Base Token deposited by a user
   */
  function getUserDepositAmount(address account)
    external
    view
    returns (uint256);
}

