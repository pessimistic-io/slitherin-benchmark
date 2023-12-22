// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address _to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address _to, uint deadline)
        external
        returns (uint[] memory amounts);
}
