// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IERC20} from "./IERC20.sol";

interface ILBRouter {
    enum Version {
        V1,
        V2,
        V2_1
    }

    struct Path {
        uint256[] pairBinSteps;
        Version[] versions;
        IERC20[] tokenPath;
    }

    function getSwapIn(
        address LBPair,
        uint128 amountOut,
        bool swapForY
    )
        external
        view
        returns (uint128 amountIn, uint128 amountOutLeft, uint128 fee);

    function getSwapOut(
        address LBPair,
        uint128 amountIn,
        bool swapForY
    )
        external
        view
        returns (uint128 amountInLeft, uint128 amountOut, uint128 fee);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

