// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapPair {
    event Sync(uint112 reserve0, uint112 reserve1);

    function sync() external;

    function approve(address spender, uint256 amount) external returns (bool);
}

