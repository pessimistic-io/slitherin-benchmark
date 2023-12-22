// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

import {IPriceCheckerLogicBase} from "./IPriceCheckerLogicBase.sol";

/// @title IPriceCheckerLogicUniswap - PriceCheckerLogicUniswap interface.
interface IPriceCheckerLogicUniswap is IPriceCheckerLogicBase {
    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the price checker
    /// @param uniswapPool The uniswap pool to check the price from.
    /// @param targetRate The target exchange rate between the tokens.
    /// @param pointer The bytes32 pointer value.
    function priceCheckerUniswapInitialize(
        IUniswapV3Pool uniswapPool,
        uint256 targetRate,
        bytes32 pointer
    ) external;

    // =========================
    // Main functions
    // =========================

    /// @notice Checks if the current rate is greater than the target rate.
    /// @param pointer The bytes32 pointer value.
    /// @return true if the current rate is greater than the target rate, otherwise false.
    function uniswapCheckGTTargetRate(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if the current rate is greater than or equal to the target rate.
    /// @param pointer The bytes32 pointer value.
    /// @return bool indicating whether the current rate is greater than or equal to the target rate.
    function uniswapCheckGTETargetRate(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if the current rate is less than the target rate.
    /// @param pointer The bytes32 pointer value.
    /// @return true if the current rate is less than the target rate, otherwise false.
    function uniswapCheckLTTargetRate(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if the current rate is less than or equal to the target rate.
    /// @param pointer The bytes32 pointer value.
    /// @return bool indicating whether the current rate is less than or equal to the target rate.
    function uniswapCheckLTETargetRate(
        bytes32 pointer
    ) external view returns (bool);

    // =========================
    // Setters
    // =========================

    /// @notice Sets the tokens and feeTier from the pair to checker storage.
    /// @param uniswapPool The uniswap pool to fetch the tokens and fee from.
    /// @param pointer The bytes32 pointer value.
    function uniswapChangeTokensAndFeePriceChecker(
        IUniswapV3Pool uniswapPool,
        bytes32 pointer
    ) external;

    /// @notice Set the target rate of the contract.
    /// @param targetRate The new target rate to be set.
    /// @param pointer The bytes32 pointer value.
    function uniswapChangeTargetRate(
        uint256 targetRate,
        bytes32 pointer
    ) external;

    // =========================
    // Getters
    // =========================

    /// @notice Retrieves the local price checker storage values.
    /// @param pointer The bytes32 pointer value.
    /// @return token0 The address of the first token.
    /// @return token1 The address of the second token.
    /// @return fee The fee for the pool.
    /// @return targetRate The target exchange rate set for the tokens.
    /// @return initialized A boolean indicating if the contract has been initialized or not.
    function uniswapGetLocalPriceCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint256 targetRate,
            bool initialized
        );
}

