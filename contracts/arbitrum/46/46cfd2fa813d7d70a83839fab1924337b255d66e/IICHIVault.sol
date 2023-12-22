// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IICHIVault {

  function ichiVaultFactory() external view returns(address);

  // This is for ICHIVaults that were created for Ramses DEX pools
  function collectRewards() external;
}

