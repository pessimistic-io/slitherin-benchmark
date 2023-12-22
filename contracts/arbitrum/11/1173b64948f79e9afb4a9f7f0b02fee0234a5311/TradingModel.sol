// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @param traderSelector the Selector of the Dex you want to use. If not sure, you can find them in VestaDexTrader.sol
 * @param tokenInOut the token0 is the one that will be swapped, the token1 is the one that will be returned
 * @param data the encoded structure for the exchange function of a ITrader.
 * @dev {data}'s structure should have 0 for expectedAmountIn and expectedAmountOut
 */
struct ManualExchange {
	bytes16 traderSelector;
	address[2] tokenInOut;
	bytes data;
}

/**
 * @param path
 * 	SingleHop: abi.encode(address tokenOut,uint24 poolFee);
 * 	MultiHop-ExactAmountIn: abi.encode(tokenIn, uint24 fee, tokenOutIn, fee, tokenOut);
 * @param tokenIn the token that will be swapped
 * @param expectedAmountIn the expected amount In that will be swapped
 * @param expectedAmountOut the expected amount Out that will be returned
 * @param amountInMaximum the maximum tokenIn that can be used
 * @param usingHop does it use a hop (multi-path)
 *
 * @dev you can only use one of the expectedAmount, not both.
 * @dev amountInMaximum can be zero
 */
struct UniswapV3SwapRequest {
	bytes path;
	address tokenIn;
	uint256 expectedAmountIn;
	uint256 expectedAmountOut;
	uint256 amountInMaximum;
	bool usingHop;
}

/**
 * @param pool the curve's pool address
 * @param coins coins0 is the token that goes in, coins1 is the token that goes out
 * @param expectedAmountIn the expect amount in that will be used
 * @param expectedAmountOut the expect amount out that the user will receives
 * @param slippage allowed slippage in BPS percentage
 * @dev {_slippage} is only used for curve and it is an addition to the expected amountIn that the system calculates.
		If the system expects amountIn to be 100 to have the exact amountOut, the total of amountIn WILL BE 110.
		You'll need it on major price impacts trading.
 *
 * @dev you can only use one of the expectedAmount, not both.
 * @dev slippage should only used by other contracts. Otherwise, do the formula off-chain and set it to zero.
 */
struct CurveSwapRequest {
	address pool;
	uint8[2] coins;
	uint256 expectedAmountIn;
	uint256 expectedAmountOut;
	uint16 slippage;
}

/**
 * @param path uses the token address to create the path
 * @param expectedAmountIn the expect amount in that will be used
 * @param expectedAmountOut the expect amount out that the user will receives
 *
 * @dev Path length should be 2 or 3. Otherwise, you are using it wrong!
 * @dev you can only use one of the expectedAmount, not both.
 */
struct GenericSwapRequest {
	address[] path;
	uint256 expectedAmountIn;
	uint256 expectedAmountOut;
}

/**
 * @param pool the curve's pool address
 * @param coins coins0 is the token that goes in, coins1 is the token that goes out
 * @param amount the amount wanted
 * @param slippage allowed slippage in BPS percentage
 * @dev {_slippage} is only used for curve and it is an addition to the expected amountIn that the system calculates.
		If the system expects amountIn to be 100 to have the exact amountOut, the total of amountIn WILL BE 110.
		You'll need it on major price impacts trading.
 */
struct CurveRequestExactInOutParams {
	address pool;
	uint8[2] coins;
	uint256 amount;
	uint16 slippage;
}

/**
 * @param path uses the token address to create the path
 * @param amount the wanted amount
 */
struct GenericRequestExactInOutParams {
	address[] path;
	uint256 amount;
}

/**
 * @param path
 * 	SingleHop: abi.encode(address tokenOut,uint24 poolFee);
 * 	MultiHop-ExactAmountIn: abi.encode(tokenIn, uint24 fee, tokenOutIn, fee, tokenOut);
 * @param tokenIn the token that will be swapped
 * @param amount the amount wanted
 * @param usingHop does it use a hop (multi-path)
 */
struct UniswapV3RequestExactInOutParams {
	bytes path;
	address tokenIn;
	uint256 amount;
	bool usingHop;
}


