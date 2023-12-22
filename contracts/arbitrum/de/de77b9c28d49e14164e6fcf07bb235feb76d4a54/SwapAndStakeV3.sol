// SPDX-License-Identifier: MIT
pragma solidity =0.8.7;
pragma abicoder v2;

import "./ISwapRouter.sol";
import "./IQuoter.sol";
import {ILockup} from "./ILockup.sol";
import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";

contract SwapAndStakeV3 {
	// solhint-disable-next-line const-name-snakecase
	ISwapRouter public constant uniswapRouter =
		ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
	// solhint-disable-next-line const-name-snakecase
	IQuoter public constant quoter =
		IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

	address public wethAddress;
	address public devAddress;
	address public lockupAddress;
	address public sTokensAddress;

	constructor(
		address _wethAddress,
		address _devAddress,
		address _lockupAddress,
		address _sTokensAddress
	) {
		wethAddress = _wethAddress;
		devAddress = _devAddress;
		lockupAddress = _lockupAddress;
		sTokensAddress = _sTokensAddress;
	}

	function swapEthAndStakeDev(address property) external payable {
		require(msg.value > 0, "Must pass non 0 ETH amount");

		// solhint-disable-next-line not-rely-on-time
		uint256 deadline = block.timestamp + 15; // using 'now' for convenience, for mainnet pass deadline from frontend!
		address tokenIn = wethAddress;
		address tokenOut = devAddress;
		// V3 ETH-DEV pair fee is 1%
		uint24 fee = 10000;
		address recipient = address(this);
		uint256 amountIn = msg.value;
		uint256 amountOutMinimum = 1;
		uint160 sqrtPriceLimitX96 = 0;

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
			.ExactInputSingleParams(
				tokenIn,
				tokenOut,
				fee,
				recipient,
				deadline,
				amountIn,
				amountOutMinimum,
				sqrtPriceLimitX96
			);
		uint256 amountOut = uniswapRouter.exactInputSingle{value: msg.value}(
			params
		);
		IERC20(devAddress).approve(lockupAddress, amountOut);
		uint256 tokenId = ILockup(lockupAddress).depositToProperty(
			property,
			amountOut
		);
		IERC721(sTokensAddress).safeTransferFrom(
			address(this),
			msg.sender,
			tokenId
		);
	}

	// do not used on-chain, gas inefficient!
	function getEstimatedDevForEth(uint256 ethAmount)
		external
		returns (uint256)
	{
		address tokenIn = wethAddress;
		address tokenOut = devAddress;
		// V3 ETH-DEV pair fee is 1%
		uint24 fee = 10000;
		uint160 sqrtPriceLimitX96 = 0;

		return
			quoter.quoteExactInputSingle(
				tokenIn,
				tokenOut,
				fee,
				ethAmount,
				sqrtPriceLimitX96
			);
	}

	// do not used on-chain, gas inefficient!
	function getEstimatedEthForDev(uint256 devAmount)
		external
		returns (uint256)
	{
		address tokenIn = wethAddress;
		address tokenOut = devAddress;
		// V3 ETH-DEV pair fee is 1%
		uint24 fee = 10000;
		uint160 sqrtPriceLimitX96 = 0;

		return
			quoter.quoteExactOutputSingle(
				tokenIn,
				tokenOut,
				fee,
				devAmount,
				sqrtPriceLimitX96
			);
	}
}

