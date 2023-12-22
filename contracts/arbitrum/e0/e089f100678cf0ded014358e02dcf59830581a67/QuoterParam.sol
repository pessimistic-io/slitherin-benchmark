// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

struct TimeswapV2PeripheryNoDexQuoterAddLiquidityGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address liquidityTo;
  bool isToken0;
  uint256 tokenAmount;
  bytes erc1155Data;
}

struct TimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address tokenTo;
  bool isToken0;
  uint160 liquidityAmount;
  uint256 excessLong0Amount;
  uint256 excessLong1Amount;
  uint256 excessShortAmount;
}

struct TimeswapV2PeripheryNoDexQuoterCollectParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  uint256 excessShortAmount;
}

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

struct TimeswapV2PeripheryNoDexQuoterShortAfterMaturityParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  uint256 positionAmount;
}

