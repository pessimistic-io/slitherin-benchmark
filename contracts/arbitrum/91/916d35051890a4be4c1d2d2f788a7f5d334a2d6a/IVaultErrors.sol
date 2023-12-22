// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

/**
 * @dev Attempted to deposit when deposits are disabled.
 */
error DepositsDisabled();

/**
 * @dev Attempted to call contract functions when emergency exit mode is enabled.
 */
error EmergencyExitEnabled();

/**
 * @dev Attempted to call contract functions when emergency exit mode is disabled.
 */
error EmergencyExitDisabled();

/**
 * @dev Attempted to deposit less than balance in wallet.
 */
error InsufficientBalance(uint256 amount, uint256 balance);

/**
 * @dev Attempted to deposit with less allowance than required.
 */
error InsufficientAllowance(uint256 amount, uint256 allowance);

/**
 * @dev Attempted to deposit less assets than the min amount for `receiver`.
 */
error BelowMinDeposit(address receiver, uint256 assets, uint256 min);

/**
 * @dev Attempted to mint less shares than the min amount for `receiver`.
 */
error BelowMinMint(address receiver, uint256 shares, uint256 min);

/**
 * @dev Attempted to deposit more assets than the max amount for `receiver`.
 */
error ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

/**
 * @dev Attempted to mint more shares than the max amount for `receiver`.
 */
error ExceededMaxMint(address receiver, uint256 shares, uint256 max);

/**
 * @dev Attempted to withdraw more assets than the max amount for `receiver`.
 */
error ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

/**
 * @dev Attempted to redeem more shares than the max amount for `receiver`.
 */
error ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

