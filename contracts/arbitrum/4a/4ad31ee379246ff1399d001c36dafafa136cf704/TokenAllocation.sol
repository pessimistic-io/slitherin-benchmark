// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PositionType} from "./PositionType.sol";

uint32 constant PERCENTAGE_DIVISOR = 1000;

struct TokenAllocation {
  uint256 percentage;
  address tokenAddress;
  string symbol;
  uint256 leverage;
  PositionType positionType;
}

