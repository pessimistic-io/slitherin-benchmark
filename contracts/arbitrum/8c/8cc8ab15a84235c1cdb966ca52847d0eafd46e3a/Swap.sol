// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./ConfigurationParam.sol";
import "./IPriceFeed.sol";

contract Swap {
    address public routerAddress = ConfigurationParam.ROUTER_ADDRESS;
    ISwapRouter public immutable swapRouter = ISwapRouter(routerAddress);

    uint24 public poolFee = 3000;
    event Log(string funName, address from, address to, address fromCion, address toCoin, uint256 value);

    function updatePoolFee(uint24 _poolFee) external returns (bool) {
        require(_poolFee > 0, "poolFee is zero");
        poolFee = _poolFee;
        return true;
    }

    function swapExactInputSingle(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        address recipient
    ) external returns (bool, uint256) {
        require(amountIn > 0, "BasePositionManager: value Anomaly");
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uint256 amountOut = swapRouter.exactInputSingle(params);
        emit Log("swapExactInputSingle", msg.sender, recipient, tokenIn, tokenOut, amountOut);
        return (true, amountOut);
    }

    function swapExactOutputSingle(
        uint256 amountOut,
        uint256 amountInMaximum,
        address tokenIn,
        address tokenOut,
        address recipient
    ) external returns (bool, uint256) {
        require(amountOut > 0, "BasePositionManager: value Anomaly");
        require(amountInMaximum > 0, "BasePositionManager: value Anomaly");
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountInMaximum);

        // Approve the router to spend the specifed `amountInMaximum` of DAI.
        // In production, you should choose the maximum amount to spend based on oracles or other data sources to acheive a better swap.
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountInMaximum);
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: recipient,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        uint256 amountIn = swapRouter.exactOutputSingle(params);
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
            TransferHelper.safeTransfer(tokenIn, msg.sender, amountInMaximum - amountIn);
        }
        emit Log("swapExactOutputSingle", msg.sender, recipient, tokenIn, tokenOut, amountOut);
        emit Log("swapExactOutputSingle", msg.sender, recipient, tokenIn, tokenIn, amountInMaximum - amountIn);
        return (true, amountIn);
    }

    function getTokenPrice(address token) external view returns (uint256) {
        IPriceFeed priceFeed = IPriceFeed(token);
        int256 price = priceFeed.latestAnswer();
        require(price > 0, "OraclePriceFeed: invalid price");
        return uint256(price);
    }
}

