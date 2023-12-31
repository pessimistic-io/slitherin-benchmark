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
  /// @notice Swaps amountIn of one token for as much as possible of another token
  /// @param params The parameters necessary for the swap, encoded as ExactInputSingleParams in calldata
  /// @return amountOut The amount of the received token
  function exactInputSingle(
      ExactInputSingleParams calldata params
  ) external payable returns (uint amountOut);
}
