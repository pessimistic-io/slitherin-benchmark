// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";

import { IQuoterV2 } from "./IQuoterV2.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { IWETH9 } from "./IWETH9.sol";

interface IBatchSwap {
	/** Errors */
	error InsufficientAmountOut();
	error InvalidSwap();
	error SushiswapFail();
	error FeeTooHigh();
	error Locked();
	error NotLocked();

	/** Data Types */

	enum Protocol { UniswapV3, SushiSwap, WETH }

	enum Lock { __, UNLOCKED, LOCKED }

	struct Swap {
		Protocol protocol;
		address tokenA;
		address tokenB;
		uint24 poolFee;    // Only for UniswapV3
		uint256 amountIn;  // Only for first swap
	}

	/** Immutables */

	function uniswapRouter() external view returns(ISwapRouter);
	function uniswapQuoter() external view returns(IQuoterV2);
	function sushiswapRouter() external view returns(IUniswapV2Router02);
	function weth() external view returns(IWETH9);

	/** Storage */

	function treasury() external view returns(address);
	function fee() external view returns(uint256);

	/** External Functions */

    function singleSwap(Swap memory swap, uint256 minAmountOut, address recipient) external payable;
    function batchSwap(Swap[] memory swap, uint256 minAmountOut, address recipient) external payable;

	/** View Functions */

    function singleSwapEstimateAmountOut(Swap memory swap) external view returns(uint256);
    function batchSwapEstimateAmountOut(Swap[] memory swap) external view returns(uint256);

	/** Owner Only Functions */

	function approveRouters(address[] calldata tokens) external;
	function rescueToken(address token, uint256 value) external;
	function rescueETH(uint256 value) external;
	function setFee(uint256 _fee) external;
	function setTreasury(address _treasury) external;

	/** Receive */

	receive() external payable;
}
