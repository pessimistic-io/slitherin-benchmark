// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ISwapPool {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy,
        bytes calldata data
    ) external payable returns (uint256, uint256);
}

