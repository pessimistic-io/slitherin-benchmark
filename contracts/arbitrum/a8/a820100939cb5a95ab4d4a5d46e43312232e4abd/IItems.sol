// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC1155.sol";

interface IItems is IERC1155 {
  function mint(address, uint, uint) external;
  function burn(address, uint, uint) external;
}
