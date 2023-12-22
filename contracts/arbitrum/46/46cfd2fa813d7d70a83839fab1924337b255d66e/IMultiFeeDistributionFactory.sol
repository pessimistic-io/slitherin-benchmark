// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IMultiFeeDistributionFactory {

  // events
  event StakerCreated(address indexed sender, address indexed ichiVault);

  // view functions
  function bytecodeHash() external view returns (bytes32);
  function cachedDeployData() external view returns (bytes memory);
  function vaultToStaker(address ichiVault) external view returns (address staker);

  // stateful functions
  function deployStaker(address ichiVault) external returns (address staker);
}

