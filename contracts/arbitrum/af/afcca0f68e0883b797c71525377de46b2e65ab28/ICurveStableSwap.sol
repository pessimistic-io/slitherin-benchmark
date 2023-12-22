// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICurveStableSwap {
    // state modifying functions
    function exchange(
        int128 tokenIndexFrom,
        int128 tokenIndexTo,
        uint256 dx,
        uint256 minDy
    ) external payable returns (uint256);

    function exchange_underlying(
        int128 tokenIndexFrom,
        int128 tokenIndexTo,
        uint256 dx,
        uint256 minDy
    ) external returns (uint256);
}

