// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface IPersonalVault {
  // function initialize(uint256 vaultId, address keeper, address _strategy, address[] memory inputs, bytes memory config) external payable;
  function initialize(
    uint256 _vaultId,
    address _keeper,
    address _hypervisor,
    address _hedgeToken,
    address _perpVault,
    bytes memory _config
  ) external;
  function deposit(uint256 amount) external;
  function withdraw(address recipient, uint256 amount) external;
  function prepareBurn() external;
  function run(bytes memory) external;
  function estimatedTotalAsset() external view returns (uint256);
  function name() external view returns (string memory);
  function vaultId() external view returns (uint256);
  function checkUpkeep() external view returns (bool, bytes memory);
  // function migrateStrategy() external;
  // function isFundReady() external view returns (bool);
}

