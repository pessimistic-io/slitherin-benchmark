// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./IUniswapV2Router02.sol";

interface ISwapsUni {
    function swapTokens(address _tokenIn, uint256 _amount, address _tokenOut, uint256 _amountOutMin) external returns (uint256);
    function getRouter(address _token0, address _token1) external view returns(IUniswapV2Router02);
}
