// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IWhaleswapCallee {
    function whaleswapCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

