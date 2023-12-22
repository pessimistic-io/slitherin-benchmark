// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IDexSwapCallee {
    function dexSwapCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

