// SPDX-License-Identifier: MIT

pragma solidity >=0.7.2;

import {IERC20} from "./IERC20.sol";

interface IWETH is IERC20 {
  function deposit() external payable;

  function withdraw(uint256) external;
}

