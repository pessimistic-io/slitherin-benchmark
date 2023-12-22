// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

struct TimeswapV2PeripheryNoDexAddLiquidityGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address liquidityTo;
  bool isToken0;
  uint256 tokenAmount;
  uint160 minLiquidityAmount;
  uint160 minSqrtInterestRate;
  uint160 maxSqrtInterestRate;
  uint256 deadline;
  bytes erc1155Data;
}

struct TimeswapV2PeripheryNoDexRemoveLiquidityGivenPositionParam {
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
  uint256 minToken0Amount;
  uint256 minToken1Amount;
  uint160 minSqrtInterestRate;
  uint160 maxSqrtInterestRate;
  uint256 deadline;
}

struct TimeswapV2PeripheryNoDexCollectParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  uint256 excessShortAmount;
  uint256 minToken0Amount;
  uint256 minToken1Amount;
  uint256 deadline;
}

struct TimeswapV2PeripheryNoDexLendGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  uint256 tokenAmount;
  uint256 minReturnAmount;
  uint256 deadline;
}

struct TimeswapV2PeripheryNoDexBorrowGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address tokenTo;
  address longTo;
  bool isToken0;
  bool isLong0;
  uint256 tokenAmount;
  uint256 maxPositionAmount;
  uint256 deadline;
}

struct TimeswapV2PeripheryNoDexBorrowGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address tokenTo;
  address longTo;
  bool isToken0;
  bool isLong0;
  uint256 positionAmount;
  uint256 minTokenAmount;
  uint256 deadline;
}

struct TimeswapV2PeripheryNoDexCloseBorrowGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  bool isLong0;
  uint256 positionAmount;
  uint256 maxTokenAmount;
  uint256 deadline;
}

struct TimeswapV2PeripheryNoDexCloseLendGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isToken0;
  uint256 positionAmount;
  uint256 minToken0Amount;
  uint256 minToken1Amount;
  uint256 deadline;
}

struct TimeswapV2PeripheryNoDexWithdrawParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  uint256 positionAmount;
  uint256 minToken0Amount;
  uint256 minToken1Amount;
  uint256 deadline;
}

