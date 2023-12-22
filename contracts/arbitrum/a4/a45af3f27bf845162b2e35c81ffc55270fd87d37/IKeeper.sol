// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface IKeeper {
  function initialize(address _owner) external;
  function addVault(address _vault) external;
  function removeVault(address _vault) external;
  function setUpkeepId(uint256 _id) external;
  function upkeepId() external view returns (uint256);
  function owner() external view returns (address);
  function vaultCount() external view returns (uint256);
  function transferOwnership(address newOwner) external;
}

