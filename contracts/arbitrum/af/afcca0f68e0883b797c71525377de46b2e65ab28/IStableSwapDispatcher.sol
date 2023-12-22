// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IStableSwapDispatcher {
    function swap(
        address pool, 
        bool isNativePool,
        uint8 tokenInIndex, 
        uint8 tokenOutIndex, 
        address tokenIn,
        address tokenOut,
        address to
    ) external;
    function swapUnderlying(
        address pool, 
        uint8 tokenInIndex, 
        uint8 tokenOutIndex,
        address tokenIn,
        address tokenOut,
        address to
    ) external;
}

