// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

/// @title A helper contract for executing boolean functions on arbitrary target call results
interface IPredicateHelper {
  /// @notice Checks passed time against block timestamp
  /// @return Result True if current block timestamp is lower than `time`. Otherwise, false
  function timestampBelow(uint256 time) external view returns (bool);
}

