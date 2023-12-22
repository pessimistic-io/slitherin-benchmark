// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

/**
 * @title Struct library
 * @author Buooy
 */
struct PushOptions {
  uint256 minUsdg;
  uint256 minGlp;
}

struct PullOptions {
  uint256 minOut;
}

struct CompositionToken {
  address tokenAddress;
  uint256 tokenDecimals;
  uint256 weight;
  uint256 maxPrice;
  uint256 minPrice;
}

struct LendingPoolTokenPair {
  address tokenAddress;
  address debtTokenAddress;
}
