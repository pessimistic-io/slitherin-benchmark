// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IMagicRefinery {
  function ownerOf(uint256 _realmId) external view returns (address owner);

  function mintFor(address _for, uint256 _quantity) external returns (uint256);

  function burn(uint256 _id) external;
}

