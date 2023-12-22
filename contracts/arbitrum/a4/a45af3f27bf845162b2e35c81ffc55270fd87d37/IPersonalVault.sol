// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface IPersonalVault {
  // function initialize(uint256 vaultId, address keeper, address _strategy, address[] memory inputs, bytes memory config) external payable;
  function initialize(
    uint256 _vaultId,
    address _keeper,
    address _strategy,
    address _hypervisor,
    address _hedgeToken,
    bytes memory/* _config */
  ) external;
  function deposit(uint256 amount) external;
  function withdraw(address recipient, uint256 amount) external;
  function prepareBurn() external;
  function run() external;
  function estimatedTotalAsset() external view returns (uint256);
  function strategy() external view returns (address);
  function vaultId() external view returns (uint256);
  // function migrateStrategy() external;
  // function isFundReady() external view returns (bool);
}

