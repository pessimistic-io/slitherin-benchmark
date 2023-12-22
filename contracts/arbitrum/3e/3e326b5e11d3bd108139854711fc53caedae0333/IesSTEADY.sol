// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";

interface IesSTEADY is IERC20 {
  function mint(address to, uint256 amount) external;
  function burn(uint256 amount) external;
}

