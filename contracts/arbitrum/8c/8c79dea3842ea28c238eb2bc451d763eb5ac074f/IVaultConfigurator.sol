// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IGoodEntryCore.sol";


interface IVaultConfigurator  {
  function goodEntryCore() external returns (IGoodEntryCore);
  function baseFeeX4() external returns (uint24);
  function owner() external returns (address);
  function transferOwnership(address newOwner) external;
}
