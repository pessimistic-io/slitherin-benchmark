// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IUniswapSwapRouter02 {
  struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }

  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  function exactInput(ExactInputParams memory params) external returns (uint256 amountOut);

  function exactInputSingle(
    ExactInputSingleParams memory params
  ) external returns (uint256 amountOut);
}
