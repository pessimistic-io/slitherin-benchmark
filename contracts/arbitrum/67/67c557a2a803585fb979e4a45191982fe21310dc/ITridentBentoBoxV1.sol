// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITridentBentoBoxV1 {
    function deposit(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);
}

