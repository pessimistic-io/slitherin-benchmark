// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICurveStableDispatcher {
    function exchange(
        address pool, 
        bool isNativePool,
        int128 tokenInIndex, 
        int128 tokenOutIndex, 
        address tokenIn,
        address tokenOut,
        address to
    ) external;
    function exchange_underlying(
        address pool, 
        int128 tokenInIndex, 
        int128 tokenOutIndex,
        address tokenIn,
        address tokenOut,
        address to
    ) external;
}

