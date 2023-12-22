// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGMXVault {
    function swap(
        address fromToken,
        address toToken,
        address receiver
    ) external returns (uint256 amountOut);
}

