// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IUniswapV2Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

    function token0() external returns (address);
}
