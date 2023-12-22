// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IDittoOracleV3 - DittoOracleV3 interface
interface IDittoOracleV3 {
    // =========================
    // Storage
    // =========================

    /// @notice Returns the period for which oracle gets time-weighted average price.
    function PERIOD() external returns (uint256);

    // =========================
    // Errors
    // =========================

    /// @notice This error is thrown when a sender tries to call `consult`
    /// for non-existing fee tier for provided tokens.
    error UniswapOracle_PoolNotFound();

    // =========================
    // Main function
    // =========================

    /// @notice Calculates time-weighted average price for a given UniswapV3-like pool.
    /// @param tokenIn The token that will be exchanged.
    /// @param amountIn The amount of tokens whose price is to be obtained in `tokenOut`.
    /// @param tokenOut The token in which the price will be received `tokenIn`.
    /// @param fee Fee tier in UniswapV3-like protocol.
    /// @param dexFactory Factory address of the UniswapV3-like protocol. (e.g.: Pancakeswap, Uniswap, etc.)
    /// @return amountOut The amount of tokens that the pool can approximately exhange for `amountIn`.
    /// @dev If pool with tokens and fee does not exist in the protocol, `UniswapOracle_PoolNotFound` error is thrown.
    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint24 fee,
        address dexFactory
    ) external view returns (uint256 amountOut);
}

