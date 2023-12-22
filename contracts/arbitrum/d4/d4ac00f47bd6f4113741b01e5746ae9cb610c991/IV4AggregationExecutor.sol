// SPDX-License-Identifier: MIT
// permalink:
// https://optimistic.etherscan.io/address/0x1111111254760f7ab3f16433eea9304126dcd199#code#L990
pragma solidity >=0.8.0;

/// @title Interface for making arbitrary calls during swap
interface IV4AggregationExecutor {
  /// @notice Make calls on `msgSender` with specified data
  function callBytes(address msgSender, bytes calldata data) external payable; // 0x2636f7f8
}

