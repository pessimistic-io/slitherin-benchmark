// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./Module.sol";
import "./ISwapRouter.sol";
import "./IQuoterV2.sol";
import "./TransferHelper.sol";
import "./IWETH9.sol";

/**
 * @title Limit Order Contract using uniswap V3
 * @notice The order executes when validate returns true.
 * @dev This contract implements the `Module` interface
 */
contract UniswapV3LimitOrder is Module {
	using SafeERC20 for IERC20;

	bytes32 public constant moduleId = keccak256(abi.encodePacked("UniswapV3LimitOrderV2"));

	ISwapRouter public immutable router;
	IQuoterV2 public immutable quoter;
	IWETH9 public immutable weth;
	bytes public constant depositCallData = abi.encodeWithSelector(IWETH9.deposit.selector);

	constructor(address _router, address _quoter, address payable _weth) {
		require(_router != address(0), "FW109");
		require(_quoter != address(0), "FW110");
		require(_weth != address(0), "FW111");
		router = ISwapRouter(_router);
		quoter = IQuoterV2(_quoter);
		weth = IWETH9(_weth);
	}

	/**
	 * @dev Fun.xyz will repeatedly check this validate function and call execute when validate returns true
	 */
	function validate(bytes calldata data) public returns (bool) {
		(uint24 poolFee, address tokenIn, address tokenOut, uint256 tokenInAmount, uint256 tokenOutAmount) = abi.decode(
			data,
			(uint24, address, address, uint256, uint256)
		);
		IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
			tokenIn: tokenIn,
			tokenOut: tokenOut,
			amountIn: tokenInAmount,
			fee: poolFee,
			sqrtPriceLimitX96: 0
		});
		if (tokenIn == address(weth)) {
			if (weth.balanceOf(msg.sender) < tokenInAmount && address(msg.sender).balance < tokenInAmount) {
				return false;
			}
		}
		(uint256 amountOut, , , ) = quoter.quoteExactInputSingle(params);
		return amountOut >= tokenOutAmount;
	}

	/**
	 * @dev Executes a swap from USDC to WETH using uniswap v3
	 */
	function execute(bytes calldata data) external override {
		require(validate(data), "FW101");
		(uint24 poolFee, address tokenIn, address tokenOut, uint256 tokenInAmount, uint256 tokenOutAmount) = abi.decode(
			data,
			(uint24, address, address, uint256, uint256)
		);

		if (tokenIn == address(weth) && weth.balanceOf(msg.sender) <= tokenInAmount) {
			_executeFromFunWallet(address(weth), tokenInAmount - weth.balanceOf(msg.sender), depositCallData);
			require(weth.balanceOf(msg.sender) >= tokenInAmount, "FW112");
		}

		bytes memory approveCallData = abi.encodeWithSelector(IERC20(tokenIn).approve.selector, address(router), tokenInAmount);
		bytes memory approveRespose = _executeFromFunWallet(tokenIn, 0, approveCallData);
		require(abi.decode(approveRespose, (bool)), "FW108");

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: tokenIn,
			tokenOut: tokenOut,
			fee: poolFee,
			recipient: msg.sender,
			deadline: block.timestamp,
			amountIn: tokenInAmount,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});
		bytes memory swapCalldata = abi.encodeCall(router.exactInputSingle, params);
		_executeFromFunWallet(address(router), 0, swapCalldata);
	}
}

