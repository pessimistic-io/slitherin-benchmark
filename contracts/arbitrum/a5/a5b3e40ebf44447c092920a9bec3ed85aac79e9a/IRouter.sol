// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IRouter {

    function getAmountOut(uint amountIn, address tokenIn, address tokenOut) external view returns (uint out, bool stable);

    
}
