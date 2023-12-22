// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Interface for Aave Checker Logic
/// @notice Provides methods to check and manage health factors using Aave.
interface IAaveCheckerLogic {
    // =========================
    // Storage
    // =========================

    /// @dev Storage structure for the Aave Checker
    struct AaveCheckerStorage {
        uint128 lowerHFBoundary;
        uint128 upperHFBoundary;
        address user;
        bool initialized;
    }

    // =========================
    // Events
    // =========================

    /// @notice Emitted when the Aave checker is initialized
    event AaveCheckerInitialized();

    /// @notice Emitted when new health factor boundaries are set
    /// @param lowerHFBoundary The new lower health factor boundary
    /// @param upperHFBoundary The new upper health factor boundary
    event AaveCheckerSetNewHF(uint128 lowerHFBoundary, uint128 upperHFBoundary);

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when trying to initialize an already initialized checker
    error AaveChecker_AlreadyInitialized();

    /// @notice Thrown when provided health factors are incorrect
    error AaveChecker_IncorrectHealthFators();

    /// @notice Thrown when trying to access uninitialized checker
    error AaveChecker_NotInitialized();

    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the Aave checker with given health factor boundaries and user address
    /// @param lowerHFBoundary The lower boundary for the health factor
    /// @param upperHFBoundary The upper boundary for the health factor
    /// @param user The user whose health factor is being checked
    /// @param pointer A bytes32 pointer value for storage location
    function aaveCheckerInitialize(
        uint128 lowerHFBoundary,
        uint128 upperHFBoundary,
        address user,
        bytes32 pointer
    ) external;

    // =========================
    // Main functions
    // =========================

    /// @notice Checks if the health factor is within set boundaries
    /// @param pointer A bytes32 pointer value for storage location
    /// @return A boolean indicating if the health factor is within boundaries
    function checkHF(bytes32 pointer) external view returns (bool);

    // =========================
    // Setters
    // =========================

    /// @notice Sets the boundaries for the health factor
    /// @param lowerHFBoundary The lower boundary for the health factor
    /// @param upperHFBoundary The upper boundary for the health factor
    /// @param pointer A bytes32 pointer value for storage location
    function setHFBoundaries(
        uint128 lowerHFBoundary,
        uint128 upperHFBoundary,
        bytes32 pointer
    ) external;

    // =========================
    // Getters
    // =========================

    /// @notice Retrieves the health factor boundaries
    /// @param pointer A bytes32 pointer value for storage location
    /// @return lowerHFBoundary The current lower boundary for the health factor
    /// @return upperHFBoundary The current upper boundary for the health factor
    function getHFBoundaries(
        bytes32 pointer
    ) external view returns (uint256 lowerHFBoundary, uint256 upperHFBoundary);

    /// @notice Retrieves the details of a specific local Aave checker storage
    /// @param pointer The pointer to the specific local Aave checker storage
    /// @return lowerHFBoundary The lower boundary for the health factor
    /// @return upperHFBoundary The upper boundary for the health factor
    /// @return user The address of the user related to this checker
    /// @return initialized A boolean indicating if this checker has been initialized
    function getLocalAaveCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (
            uint256 lowerHFBoundary,
            uint256 upperHFBoundary,
            address user,
            bool initialized
        );
}

