// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library Errors {

  /* ========== ERRORS ========== */

  // Authorization
  error OnlyKeeperAllowed();
  error OnlyVaultAllowed();

  // Vault deposit errors
  error EmptyDepositAmount();
  error InvalidDepositToken();
  error InsufficientDepositAmount();
  error InsufficientDepositBalance();
  error InvalidNativeDepositAmountValue();
  error InsufficientSharesMinted();
  error InsufficientCapacity();
  error InsufficientLendingLiquidity();

  // Vault withdrawal errors
  error InvalidWithdrawToken();
  error EmptyWithdrawAmount();
  error InsufficientWithdrawAmount();
  error InsufficientWithdrawBalance();
  error InsufficientAssetsReceived();

  // Vault rebalance errors
  error EmptyLiquidityProviderAmount();

  // Flash loan prevention
  error WithdrawNotAllowedInSameDepositBlock();

  // Invalid Token
  error InvalidTokenIn();
  error InvalidTokenOut();
}

