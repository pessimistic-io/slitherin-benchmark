// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IUniswapRouterV3.sol";
import "./IUniswapRouterV3WithDeadline.sol";

library UniV3Actions {
    function singleSwapV3(
        address _router,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        IUniswapRouterV3.ExactInputSingleParams memory params = IUniswapRouterV3.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        amountOut = IUniswapRouterV3(_router).exactInputSingle(params);
    }

    // Uniswap V3 swap
    function swapV3(address _router, bytes memory _path, uint256 _amount) internal returns (uint256 amountOut) {
        IUniswapRouterV3.ExactInputParams memory swapParams = IUniswapRouterV3.ExactInputParams({
            path: _path,
            recipient: address(this),
            amountIn: _amount,
            amountOutMinimum: 0
        });
        return IUniswapRouterV3(_router).exactInput(swapParams);
    }

    // Uniswap V3 swap with deadline
    function swapV3WithDeadline(
        address _router,
        bytes memory _path,
        uint256 _amount
    ) internal returns (uint256 amountOut) {
        IUniswapRouterV3WithDeadline.ExactInputParams memory swapParams = IUniswapRouterV3WithDeadline
            .ExactInputParams({
                path: _path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amount,
                amountOutMinimum: 0
            });
        return IUniswapRouterV3WithDeadline(_router).exactInput(swapParams);
    }

    // Uniswap V3 swap with deadline
    function swapV3WithDeadline(
        address _router,
        bytes memory _path,
        uint256 _amount,
        address _to
    ) internal returns (uint256 amountOut) {
        IUniswapRouterV3WithDeadline.ExactInputParams memory swapParams = IUniswapRouterV3WithDeadline
            .ExactInputParams({
                path: _path,
                recipient: _to,
                deadline: block.timestamp,
                amountIn: _amount,
                amountOutMinimum: 0
            });
        return IUniswapRouterV3WithDeadline(_router).exactInput(swapParams);
    }
}

