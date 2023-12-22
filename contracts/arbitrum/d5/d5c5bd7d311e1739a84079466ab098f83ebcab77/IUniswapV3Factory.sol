// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.9;
pragma abicoder v2;

interface IUniswapV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}

