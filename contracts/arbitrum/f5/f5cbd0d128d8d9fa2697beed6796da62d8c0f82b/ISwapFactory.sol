// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

interface ISwapFactory {

    function createPair(address tokenA, address tokenB) external returns (address pair);

}

