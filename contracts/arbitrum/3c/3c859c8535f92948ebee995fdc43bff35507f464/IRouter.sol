// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IRouter {
    struct Path {
        uint256 updated;
        PathRoute BToD; // Borrow to deposit
        PathRoute DToB; // Deposit to borrow
    }

    struct PathRoute {
        uint128 toAmountMin;
        uint8 route;
        address[] bestPath;
        uint24[] fee;
    }

    function swap(
        PathRoute memory path,
        uint256 amount,
        address receiver
    ) external returns (uint256 amountOut);
}

