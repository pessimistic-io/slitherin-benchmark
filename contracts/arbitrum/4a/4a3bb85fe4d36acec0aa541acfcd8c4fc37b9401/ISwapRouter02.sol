// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Simple SwapRouter interface to allow the UniswapSwapAdapter to be compiled in 0.8.17
interface ISwapRouter02 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

