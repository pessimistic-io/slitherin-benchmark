// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IBuyback {
    function swap(address inputToken, uint amountIn) external returns (uint);
}

