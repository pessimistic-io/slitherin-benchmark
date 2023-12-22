// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";

contract DexTrader is Ownable {
    ISwapRouter public swapRouter;
    address public executor;

    event Trade(address indexed token0, address indexed token1, uint24 fee, uint256 amountIn, uint256 amountOut, uint256 amountOutMinimum);

    modifier onlyExecutor {
        require(msg.sender == executor, "Trader: caller is not the executor");
        _;
    }

    constructor(address _router, address _executor) {
        swapRouter = ISwapRouter(_router);
        executor = _executor;
    }

    function updateRouter(address _router) external onlyOwner {
        swapRouter = ISwapRouter(_router);
    }

    function updateExecutor(address _executor) external onlyOwner {
        executor = _executor;
    }

    function trade(address token0, address token1, uint24 poolFee, uint256 amountIn, uint256 amountOutMinimum) external onlyExecutor returns (uint256 amountOut) {
        uint256 deadline = block.timestamp + 1 minutes;

        // Approve the router to spend token0.
        TransferHelper.safeApprove(token0, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: token0,
            tokenOut: token1,
            fee: poolFee,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        // The call `exactInputSingle` to execute the swap.
        amountOut = swapRouter.exactInputSingle(params); // The amount of the received token

        emit Trade(token0, token1, poolFee, amountIn, amountOut, amountOutMinimum);
        return amountOut;
    }

    /**
     * @dev withdraw erc20 token
     * @param _token erc20 token address
     * @param amount amount
     * @param recipient recipient address
     */
    function withdrawToken(address _token, uint256 amount, address recipient) external onlyOwner {
        ERC20 token = ERC20(_token);

        require(token.balanceOf(address(this)) >= amount, "insufficient balance");
        require(token.transfer(recipient, amount), 'token withdraw failed');
    }

    /**
     * @dev approve erc20 token
     * @param _token erc20 token address
     * @param spender spender
     * @param amount amount
     */
    function approve(address _token, address spender, uint256 amount) external onlyOwner {
        ERC20 token = ERC20(_token);
        require(token.approve(spender, amount), 'approve failed');
    }
}

