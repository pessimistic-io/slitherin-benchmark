// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface Uni {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] memory path
    ) external
      view
      virtual
      returns (uint[] memory amounts);
}

