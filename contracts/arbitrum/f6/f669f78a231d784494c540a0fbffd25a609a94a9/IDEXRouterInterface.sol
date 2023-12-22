// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDEXRouterInterface {
     function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}
