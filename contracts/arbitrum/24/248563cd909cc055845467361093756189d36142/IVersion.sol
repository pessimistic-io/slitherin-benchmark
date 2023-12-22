// SPDX-License-Identifier: BUSL-1.1

// (c) Gearbox Holdings, 2022

// This code was largely inspired by Gearbox Protocol

pragma solidity 0.8.16;

/// @title IVersion
/// @dev Declares a version function which returns the contract's version
interface IVersion {
  /// @dev Returns contract version
  function version() external view returns (uint256);
}

