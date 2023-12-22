// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";

interface IWETH is IERC20 {
  function withdraw(uint256 amount) external;
}

