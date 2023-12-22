// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IFeeSettlement {
    function processSettlement(address tokenOut, uint256 amountOutMin, address from, address to) external;
}

