// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct GlpTokenAllocation {
  uint256 tokenAddress;
  uint256 poolAmount;
  uint256 usdgAmount;
  uint256 weight;
  uint256 allocation;
}

