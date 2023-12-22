// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

struct TimeswapV2PeripheryNoDexQuoterLendGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  uint256 tokenAmount;
}

struct TimeswapV2PeripheryNoDexQuoterCloseBorrowGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  bool isLong0;
  uint256 positionAmount;
}

struct TimeswapV2PeripheryNoDexQuoterBorrowGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address tokenTo;
  address longTo;
  bool isToken0;
  bool isLong0;
  uint256 tokenAmount;
}

struct TimeswapV2PeripheryNoDexQuoterCloseLendGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  uint256 positionAmount;
}

struct TimeswapV2PeripheryNoDexQuoterWithdrawParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  uint256 positionAmount;
}

