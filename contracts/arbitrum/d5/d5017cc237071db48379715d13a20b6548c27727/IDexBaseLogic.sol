// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IDexBaseLogic - DexBaseLogic interface.
interface IDexBaseLogic {
    // =========================
    // Events
    // =========================

    /// @notice Emits when fees are collected from a dex position.
    event DexCollectFees(uint256 amount0, uint256 amount1);

    /// @notice Emits when a swap occurs on Dex.
    event DexSwap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut
    );

    // =========================
    // Errors
    // =========================

    /// @notice Throws when length of the tokens array in swap method less than 2.
    error DexLogicLogic_WrongLengthOfTokensArray();

    /// @notice Throws when length of the tokens array in swap method is not equal
    /// `length of the poolFees array + 1`.
    error DexLogicLogic_WrongLengthOfPoolFeesArray();
}

