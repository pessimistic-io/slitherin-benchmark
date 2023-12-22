// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IUniswapRouter is ISwapRouter {
    function refundETH() external payable;
}

contract UniV3Provider is Ownable, ReentrancyGuard {
    address private constant NATIVE_TOKEN_ADDRESS =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    IUniswapRouter public swapRouter;
    address public wrappedNative;

    uint24 public constant poolFee = 3000;

    // Uniswap router and wrapped native token address required
    constructor(address _swapRouter, address _wrappedNative) {
        swapRouter = IUniswapRouter(_swapRouter);
        wrappedNative = _wrappedNative;
    }

    /**
    // @notice function responsible to swap ERC20 -> ERC20
    // @param _tokenIn address of input token
    // @param _tokenOut address of output token
    // @param amountIn amount of input tokens
    // param extraData extra data if required
     */
    function swapERC20(
        address _receiver,
        address _tokenIn,
        address _tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(
            _tokenIn,
            msg.sender,
            address(this),
            amountIn
        );

        TransferHelper.safeApprove(_tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: poolFee,
                recipient: _receiver,
                deadline: block.timestamp + 120,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);

        // emit ERC20FundsSwapped(amountIn, _tokenIn, _tokenOut, amountOut);
    }

    /**
    // @notice function responsible to swap NATIVE -> ERC20
    // @param _tokenOut address of output token
    // param extraData extra data if required
     */
    function swapNative(
        address _tokenOut
    ) external payable returns (uint256 amountOut) {
        require(msg.value > 0, "Must pass non 0 ETH amount");

        uint256 deadline = block.timestamp + 120;
        address tokenIn = wrappedNative;
        address tokenOut = _tokenOut;
        uint24 fee = 3000;
        address recipient = msg.sender;
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

        amountOut = swapRouter.exactInputSingle{value: msg.value}(params);
        // swapRouter.refundETH();

        // refund leftover ETH to user
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "refund failed");

        // emit NativeFundsSwapped(_tokenOut, amountIn, amountOut);
    }

    /**
	// @notice function responsible to rescue funds if any
	// @param  tokenAddr address of token
	 */
    function rescueFunds(address tokenAddr) external onlyOwner nonReentrant {
        if (tokenAddr == NATIVE_TOKEN_ADDRESS) {
            uint256 balance = address(this).balance;
            payable(msg.sender).transfer(balance);
        } else {
            uint256 balance = IERC20(tokenAddr).balanceOf(address(this));
            IERC20(tokenAddr).transferFrom(address(this), msg.sender, balance);
        }
    }

    // receive() external payable {}
}

