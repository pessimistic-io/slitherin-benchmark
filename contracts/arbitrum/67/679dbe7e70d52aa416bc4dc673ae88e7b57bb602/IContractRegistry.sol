// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IContractRegistry {
    // =======================================================================
  // Getters / Setters
  // =======================================================================
  /// @notice adds a new strategy to the contract registry
  /// @param strategyAddress new strategy address
  function addNewStrategy(address strategyAddress) external;

  /// @notice Gets the strategy addresses
  /// @return strategies the set of strategy addresses
  function getStrategies() external view returns (address[] memory strategies);
}
