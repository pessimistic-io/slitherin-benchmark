// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

/// @title An interface for TS-V2 Periphery Collect Transaction Fees
interface ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity {
  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external returns (address);

  /// @dev Returns the pool factory address.
  /// @return poolFactory The pool factory address.
  function poolFactory() external returns (address);

  /// @dev Return the tokens address
  function tokens() external returns (address);

  /// @dev Return the liquidity tokens address
  function liquidityTokens() external returns (address);
}

