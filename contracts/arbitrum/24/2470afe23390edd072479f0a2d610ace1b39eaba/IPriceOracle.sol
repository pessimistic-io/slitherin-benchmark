// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

interface IPriceOracle {
    function consult(address tokenIn, uint amountIn, address tokenOut) external returns (uint amountOut);
    function consultReadonly(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut);
}
