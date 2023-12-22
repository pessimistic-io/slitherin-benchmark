// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IPriceDifferenceCheckerLogicBase} from "./IPriceDifferenceCheckerLogicBase.sol";

/// @title IPriceDifferenceCheckerLogicUniswap - PriceDifferenceCheckerLogicUniswap interface.
interface IPriceDifferenceCheckerLogicUniswap is
    IPriceDifferenceCheckerLogicBase
{
    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the PriceDifferenceChecker contract by setting the token addresses and percentage of difference.
    /// @param uniswapPool The Uniswap V3 pool for the Uniswap exchange.
    /// @param percentageDeviation_E3 The percentage of difference allowed between the two token prices.
    /// @param pointer The bytes32 pointer value.
    function priceDifferenceCheckerUniswapInitialize(
        IUniswapV3Pool uniswapPool,
        uint24 percentageDeviation_E3,
        bytes32 pointer
    ) external;

    // =========================
    // Main functions
    // =========================

    /// @notice Checks the percentage difference between the current price and the last checked price.
    /// @dev Updates the last recorded price in the state.
    /// @param pointer The bytes32 pointer value.
    /// @return success True if the percentage difference is within an acceptable range.
    function uniswapCheckPriceDifference(
        bytes32 pointer
    ) external returns (bool success);

    /// @notice Checks the percentage difference between the current price and the last checked price.
    /// @param pointer The bytes32 pointer value.
    /// @return success True if the percentage difference is within an acceptable range.
    function uniswapCheckPriceDifferenceView(
        bytes32 pointer
    ) external view returns (bool success);

    // =========================
    // Setters
    // =========================

    /// @notice Sets the tokens for the pool.
    /// @param uniswapPool The Uniswap V3 pool for the Uniswap exchange.
    /// @param pointer The bytes32 pointer value.
    function uniswapChangeTokensAndFeePriceDiffChecker(
        IUniswapV3Pool uniswapPool,
        bytes32 pointer
    ) external;

    /// @notice Sets the percentage of difference for the contract.
    /// @param percentageDeviation_E3 The percentage of difference to be set.
    /// @param pointer The bytes32 pointer value.
    function uniswapChangePercentageDeviationE3(
        uint24 percentageDeviation_E3,
        bytes32 pointer
    ) external;

    // =========================
    // Getters
    // =========================

    /// @notice Retrieves the local price difference checker storage values.
    /// @param pointer The bytes32 pointer value.
    /// @return token0 The address of the first token.
    /// @return token1 The address of the second token.
    /// @return fee The fee for the pool.
    /// @return percentageDeviation_E3 The allowed percentage deviation.
    /// @return lastCheckPrice The last recorded price.
    /// @return initialized A boolean indicating if the checker has been initialized or not.
    function uniswapGetLocalPriceDifferenceCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint24 percentageDeviation_E3,
            uint256 lastCheckPrice,
            bool initialized
        );
}

