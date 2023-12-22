// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IPriceCheckerLogicBase - PriceCheckerLogicBase interface.
interface IPriceCheckerLogicBase {
    // =========================
    // Storage
    // =========================

    /// @dev Struct to store Price Checker related data
    struct PriceCheckerStorage {
        address token0;
        address token1;
        uint24 fee;
        bool initialized;
        uint256 targetRate;
    }

    // =========================
    // Events
    // =========================

    /// @notice Emits when the Price Checker is initialized
    event PriceCheckerInitialized();

    /// @notice Emits when a new target rate is set for the Price Checker
    /// @param newTarget The new target rate set
    event PriceCheckerSetNewTarget(uint256 newTarget);

    /// @notice Emits when new tokens and fee are set for the Price Checker
    /// @param token0 Address of token0
    /// @param token1 Address of token1
    /// @param fee The fee associated with the token pair
    event PriceCheckerSetNewTokensAndFee(
        address token0,
        address token1,
        uint24 fee
    );
    // =========================
    // Errors
    // =========================

    /// @notice Thrown when trying to initialize an already initialized Price Checker
    error PriceChecker_AlreadyInitialized();

    /// @notice Thrown when trying to perform an action on a not initialized Price Checker
    error PriceChecker_NotInitialized();
}

