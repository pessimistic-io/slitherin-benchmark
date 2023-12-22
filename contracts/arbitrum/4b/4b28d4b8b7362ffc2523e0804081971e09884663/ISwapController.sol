// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface ISwapController {
    function swap(address tokenIn, uint256 amount, uint256 minAmount, address to) external;
}
