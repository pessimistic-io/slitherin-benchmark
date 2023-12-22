//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

interface IChronosRouter {
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external;
}

