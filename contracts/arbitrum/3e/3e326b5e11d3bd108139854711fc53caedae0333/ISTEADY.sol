// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";

interface ISTEADY is IERC20 {
  function burn(uint256 amount) external;
}

