// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IWombatRouter {
    function swapExactTokensForTokens(
        address[] calldata tokenPath,
        address[] calldata poolPath,
        uint256 fromAmount,
        uint256 minimumToAmount,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

