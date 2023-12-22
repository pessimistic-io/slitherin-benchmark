// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

struct route {
    address from;
    address to;
    bool stable;
}

interface IRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountA,
        uint amountB,
        uint amountMinA,
        uint amountMinB,
        address to,
        uint deadline
    ) external returns (uint a, uint b, uint l);

    function addLiquidityETH(
        address token,
        bool stable,
        uint amountDesired,
        uint amountMin,
        uint amountMinETH,
        address to,
        uint deadline
    ) external payable returns (uint a, uint b, uint l);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountOut(uint amountIn, address tokenIn, address tokenOut) external view returns (uint out, bool stable);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity
    ) external view returns (uint amountA, uint amountB);
}
