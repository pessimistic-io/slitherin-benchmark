// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.7;
pragma abicoder v2;

import "./ISwapRouter.sol";
import "./IQuoter.sol";
import {ILockup} from "./ILockup.sol";
import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";
import "./Escrow.sol";

contract SwapAndStakeV3 is Escrow {
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
	struct Amounts {
		uint256 input;
		uint256 fee;
	}
	mapping(address => Amounts) public gatewayOf;

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

	/// @notice Swap eth -> dev and stake
	/// @param property the property to stake after swap
	/// @param deadline refer to https://docs.uniswap.org/protocol/V1/guides/trade-tokens#deadlines
	/// @param payload allows for additional data when minting SToken
	function swapEthAndStakeDev(
		address property,
		uint256 deadline,
		bytes32 payload
	) external payable {
		require(msg.value > 0, "Must pass non 0 ETH amount");

		gatewayOf[address(0)] = Amounts(msg.value, 0);

		_swapEthAndStakeDev(msg.value, property, deadline, payload);

		delete gatewayOf[address(0)];
	}

	/// @notice Swap eth -> dev and stake with GATEWAY FEE (paid in ETH) and payload
	/// @param property the property to stake after swap
	/// @param deadline refer to https://docs.uniswap.org/protocol/V1/guides/trade-tokens#deadlines
	/// @param payload allows for additional data when minting SToken
	/// @param gatewayAddress is the address to which the liquidity provider fee will be directed
	/// @param gatewayFee is the basis points to pass. For example 10000 is 100%
	function swapEthAndStakeDev(
		address property,
		uint256 deadline,
		bytes32 payload,
		address payable gatewayAddress,
		uint256 gatewayFee
	) external payable {
		require(gatewayFee <= 10000, "must be below 10000");

		// handle fee
		uint256 feeAmount = (msg.value * gatewayFee) / 10000;
		_deposit(gatewayAddress, feeAmount, address(0));

		gatewayOf[gatewayAddress] = Amounts(msg.value, feeAmount);

		_swapEthAndStakeDev(
			(msg.value - feeAmount),
			property,
			deadline,
			payload
		);

		delete gatewayOf[gatewayAddress];
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

	//=================================== PRIVATE ==============================================
	/// @notice Swap eth -> dev handles transfer and stake with payload
	/// @param amount in ETH
	/// @param property the property to stake after swap
	/// @param deadline refer to https://docs.uniswap.org/protocol/V1/guides/trade-tokens#deadlines
	/// @param payload allows for additional data when minting SToken
	function _swapEthAndStakeDev(
		uint256 amount,
		address property,
		uint256 deadline,
		bytes32 payload
	) private {
		address tokenIn = wethAddress;
		address tokenOut = devAddress;
		// V3 ETH-DEV pair fee is 1%
		uint24 fee = 10000;
		address recipient = address(this);
		uint256 amountIn = amount;
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
		uint256 amountOut = uniswapRouter.exactInputSingle{value: amount}(
			params
		);
		IERC20(devAddress).approve(lockupAddress, amountOut);
		uint256 tokenId = ILockup(lockupAddress).depositToProperty(
			property,
			amountOut,
			payload
		);
		IERC721(sTokensAddress).safeTransferFrom(
			address(this),
			msg.sender,
			tokenId
		);
	}
}

