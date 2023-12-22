// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IOneInchV4Swapper {
    struct SwapParams {
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 minAmountOut;
        bytes externalData;
    }

    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 minAmountOut, bytes memory externalData)
        external
        returns (uint256 amountOut);
}

