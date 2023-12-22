// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITrade {
    function trade(uint256 _type,  address router, uint256 amountIn, uint256 amountOutMin, address[] calldata path) external;
}

