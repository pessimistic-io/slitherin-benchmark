// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISwappoor {
    function swapTokens(address tokenA, address tokenB, uint amount) external returns (uint);
    function priceOutOfSync() external view returns (bool state);
    function weth() external view returns (address);
    function zapIn(bool isWeth, uint amountA, address to) external;
}
