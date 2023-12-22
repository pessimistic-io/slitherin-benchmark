// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

struct TimeswapV2PeripheryUniswapV3QuoterCollectTransactionFeesParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  uint24 uniswapV3Fee;
  address tokenTo;
  address excessLong0To;
  address excessLong1To;
  address excessShortTo;
  bool isToken0;
  uint256 long0Requested;
  uint256 long1Requested;
  uint256 shortRequested;
}

struct TimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  uint24 uniswapV3Fee;
  address liquidityTo;
  bool isToken0;
  uint256 tokenAmount;
}

struct TimeswapV2PeripheryUniswapV3QuoterRemoveLiquidityGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  uint24 uniswapV3Fee;
  address tokenTo;
  address excessLong0To;
  address excessLong1To;
  address excessShortTo;
  bool isToken0;
  bool preferLong0Excess;
  uint160 liquidityAmount;
}

struct TimeswapV2PeripheryUniswapV3QuoterLendGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  uint24 uniswapV3Fee;
  address to;
  bool isToken0;
  uint256 tokenAmount;
}

struct TimeswapV2PeripheryUniswapV3QuoterCloseBorrowGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  uint24 uniswapV3Fee;
  address to;
  bool isToken0;
  bool isLong0;
  uint256 positionAmount;
}

struct TimeswapV2PeripheryUniswapV3QuoterBorrowGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  uint24 uniswapV3Fee;
  address tokenTo;
  address longTo;
  bool isToken0;
  bool isLong0;
  uint256 tokenAmount;
}

struct TimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  uint24 uniswapV3Fee;
  address to;
  bool isToken0;
  uint256 positionAmount;
}

struct TimeswapV2PeripheryUniswapV3QuoterWithdrawParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  uint24 uniswapV3Fee;
  address to;
  bool isToken0;
  uint256 positionAmount;
}

struct UniswapV3SwapQuoterParam {
  bool zeroForOne;
  bool exactInput;
  uint256 amount;
  uint256 strikeLimit;
  bytes data;
}

struct UniswapV3SwapForRebalanceQuoterParam {
  bool zeroForOne;
  bool exactInput;
  uint256 amount;
  uint256 strikeLimit;
  uint256 transactionFee;
  bytes data;
}

