// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface IPersonalVault {
  function initialize(uint256 vaultId, address keeper, address _strategy, address[] memory inputs, bytes memory config) external;
  function deposit(uint256 amount) external;
  function withdraw(address recipient, uint256 amount, bool forced) external;
  function run() external payable;
  function estimatedTotalAsset() external view returns (uint256);
  function strategy() external view returns (address);
}

