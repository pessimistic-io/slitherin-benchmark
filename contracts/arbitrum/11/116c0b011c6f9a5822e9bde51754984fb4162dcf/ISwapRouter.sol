// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ISwapRouter {
  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint deadline;
    uint amountIn;
    uint amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  function exactInputSingle(
      ExactInputSingleParams calldata params
  ) external payable returns (uint amountOut);
}
