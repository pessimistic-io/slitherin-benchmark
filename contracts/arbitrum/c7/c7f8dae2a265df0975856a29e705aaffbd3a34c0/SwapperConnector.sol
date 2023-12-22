// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ISwapperConnector.sol";

/**
 * @title SwapperConnector Contract
 * @notice This contract manages the swapper connector configuration for the smart contract.
 */
abstract contract SwapperConnector is ISwapperConnector {
    /**
    @notice Calculates the amount of input tokens needed to receive the specified amount of output tokens.
    @param path The path of the tokens to swap.
    @param amountOut The desired amount of output tokens.
    @return amountIn The amount of input tokens needed to receive the specified amount of output tokens.
    */
    function getAmountIn(bytes memory path, uint256 amountOut) external virtual override returns (uint256 amountIn);

    /**
    @notice Swaps a specified amount of input tokens for output tokens.
    @param path The path of the tokens to swap.
    @param tokenIn The address of the input token.
    @param amountIn The amount of input tokens to swap.
    @param recipient The address to send the output tokens to.
    @return amountOut The amount of output tokens received from the swap.
    */
    function swap(
        bytes memory path,
        address tokenIn,
        uint256 amountIn,
        address recipient
    ) external virtual override returns (uint256 amountOut);
}

