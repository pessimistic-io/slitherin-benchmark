// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IUniswapV3Pool {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

