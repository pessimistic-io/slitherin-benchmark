// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8;

interface IUniV3Callback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external;
}

