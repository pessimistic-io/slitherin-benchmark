// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IUniswapV3Factory {
    function getPool(address, address, uint24) external view returns (address);
}

