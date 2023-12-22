// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IPriceDifferenceCheckerLogicBase - PriceDifferenceCheckerLogicBase interface.
interface IPriceDifferenceCheckerLogicBase {
    // =========================
    // Storage
    // =========================

    /// @notice Storage structure for managing price difference checker data.
    struct PriceDifferenceCheckerStorage {
        // Address of the first token.
        address token0;
        // Address of the second token.
        address token1;
        // Fee associated with the token pair.
        uint24 fee;
        // Allowed percentage deviation.
        uint24 percentageDeviation_E3;
        // Flag indicating if the checker has been initialized.
        bool initialized;
        // The last recorded check price.
        uint256 lastCheckPrice;
    }

    // =========================
    // Events
    // =========================

    /// @notice Emits when the Price Difference Checker is initialized.
    event PriceDifferenceCheckerInitialized();

    /// @notice Emits when a new deviation threshold is set.
    /// @param newPercentage The new percentage deviation threshold.
    event PriceDifferenceCheckerSetNewDeviationThreshold(uint24 newPercentage);

    /// @notice Emits when new tokens and fee are set.
    /// @param token0 Address of the first token.
    /// @param token1 Address of the second token.
    /// @param fee Associated fee with the token pair.
    event PriceDifferenceCheckerSetNewTokensAndFee(
        address token0,
        address token1,
        uint24 fee
    );

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when trying to initialize an already initialized Price
    /// Difference Checker
    error PriceDifferenceChecker_AlreadyInitialized();

    /// @notice Thrown when trying to provide an invalid percentage deviation
    /// to constructor or setter
    error PriceDifferenceChecker_InvalidPercentageDeviation();

    /// @notice Thrown when trying to perform an action on a not initialized
    /// Price Difference Checker
    error PriceDifferenceChecker_NotInitialized();
}

