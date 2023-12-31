// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @custom:doc Uniswap V3's Doc
 */

struct ExactInputSingleParams {
	address tokenIn;
	address tokenOut;
	uint24 fee;
	address recipient;
	uint256 deadline;
	uint256 amountIn;
	uint256 amountOutMinimum;
	uint160 sqrtPriceLimitX96;
}

struct ExactOutputSingleParams {
	address tokenIn;
	address tokenOut;
	uint24 fee;
	address recipient;
	uint256 deadline;
	uint256 amountOut;
	uint256 amountInMaximum;
	uint160 sqrtPriceLimitX96;
}

struct ExactInputParams {
	bytes path;
	address recipient;
	uint256 deadline;
	uint256 amountIn;
	uint256 amountOutMinimum;
}

struct ExactOutputParams {
	bytes path;
	address recipient;
	uint256 deadline;
	uint256 amountOut;
	uint256 amountInMaximum;
}

