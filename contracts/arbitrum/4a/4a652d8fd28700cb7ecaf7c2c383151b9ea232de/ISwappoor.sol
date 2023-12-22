// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ISwappoor {
    function swapTokens(address tokenA, address tokenB, uint amount) external returns (uint);
}
