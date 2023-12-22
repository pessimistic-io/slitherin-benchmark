// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

uint32 constant PERCENTAGE_DIVISOR = 1000;

struct TokenAllocation {
  uint256 percentage;
  address tokenAddress;
  uint256 leverage;
}

