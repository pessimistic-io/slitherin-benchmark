// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

interface ICustomSwapRouter {
    function exchangeToken(
        uint256 amount,
        uint256 beliefPrice
    ) external returns (uint256 amountOut);
}

