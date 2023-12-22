// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ISwapperConnector.sol";

abstract contract SwapperConnector is ISwapperConnector {
    function getAmountIn(bytes memory path, uint256 amountOut) external override virtual returns (uint256 amountIn);

    function swap(
        bytes memory path,
        address tokenIn,
        uint256 amountIn,
        address recipient
    ) external override virtual returns (uint256 amountOut);
}

