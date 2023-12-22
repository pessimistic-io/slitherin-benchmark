// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICamelotFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface ICamelotPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function getAmountOut(uint amountIn, address tokenIn) external view returns (uint);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);
}

