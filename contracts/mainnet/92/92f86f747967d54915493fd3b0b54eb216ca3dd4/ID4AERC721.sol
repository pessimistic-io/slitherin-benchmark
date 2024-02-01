// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

interface ID4AERC721{
  function mintItem(address player, string memory tokenURI) external returns (uint256);
}

