// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./UniswapV3Model.sol";

interface ISwapRouter {
	function exactInputSingle(ExactInputSingleParams calldata params)
		external
		payable
		returns (uint256 amountOut);

	function exactInput(ExactInputParams calldata params)
		external
		payable
		returns (uint256 amountOut);

	function exactOutputSingle(ExactOutputSingleParams calldata params)
		external
		returns (uint256 amountIn);

	function exactOutput(ExactOutputParams calldata params)
		external
		returns (uint256 amountIn);
}

