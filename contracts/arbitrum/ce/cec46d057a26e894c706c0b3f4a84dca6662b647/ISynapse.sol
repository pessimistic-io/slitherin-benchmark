// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISynapse {

    function swapAndRedeem(
        address to,
        uint256 chainId,
        address token,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external;
}

