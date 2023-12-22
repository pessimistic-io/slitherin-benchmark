// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;
pragma abicoder v2;

import { IERC20 } from "./IERC20.sol";

interface IWBase is IERC20 {
  function deposit() external payable;

  function withdraw(uint256) external;
}

