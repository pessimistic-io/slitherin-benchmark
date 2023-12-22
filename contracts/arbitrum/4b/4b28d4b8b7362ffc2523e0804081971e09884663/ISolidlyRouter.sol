// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface ISolidlyRouter {
    struct route {
        address from;
        address to;
        bool stable;
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        route[] memory routes,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}
