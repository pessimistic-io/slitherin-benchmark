// SPDX-License-Identifier: No License

pragma solidity >=0.6.2;

interface IUniswapV2Router {
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function getAmountsIn(uint amountOut, address[] calldata path)
        external
        view
        returns (uint[] memory amounts);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

