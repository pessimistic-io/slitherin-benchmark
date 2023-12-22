// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISwapStrategy {
    
    function swapExactTokensForTokens(address router, uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external;
    function swapExactETHForTokens(address router, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external payable;
    function swapExactTokensForETH(address router, uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external;
    function getAmountsOut(address router, uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
}
