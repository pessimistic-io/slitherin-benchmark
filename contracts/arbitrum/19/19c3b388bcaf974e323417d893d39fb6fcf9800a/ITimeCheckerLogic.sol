// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ITimeCheckerLogic - TimeCheckerLogic interface.
interface ITimeCheckerLogic {
    // =========================
    // Storage
    // =========================

    /// @dev Storage structure for the Time Checker
    struct TimeCheckerStorage {
        uint64 lastActionTime;
        uint64 timePeriod;
        bool initialized;
    }

    // =========================
    // Events
    // =========================

    /// @notice Thrown when a new period is set for the TimeChecker.
    /// @param newPeriod The new period that was set.
    event TimeCheckerSetNewPeriod(uint256 newPeriod);

    /// @notice Thrown when the TimeChecker is initialized.
    event TimeCheckerInitialized();

    /// @notice Thrown when trying to initialize an already initialized Time Checker
    error TimeChecker_AlreadyInitialized();

    /// @notice Thrown when trying to perform an action on a not initialized Time Checker
    error TimeChecker_NotInitialized();

    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the time checker with the given parameters.
    /// @param lastActionTime Start time from which calculations will be started.
    /// @param timePeriod Delay between available call in seconds.
    /// @param pointer The bytes32 pointer value.
    function timeCheckerInitialize(
        uint64 lastActionTime,
        uint64 timePeriod,
        bytes32 pointer
    ) external;

    // =========================
    // Main functions
    // =========================

    /// @notice Check if enough time has elapsed since the last action.
    /// @dev Updates the `lastActionTime` in state if enough time has elapsed.
    /// @param pointer The bytes32 pointer value.
    /// @return A boolean indicating whether enough time has elapsed.
    function checkTime(bytes32 pointer) external returns (bool);

    /// @notice Check if enough time has elapsed since the last action.
    /// @param pointer The bytes32 pointer value.
    /// @return A boolean indicating whether enough time has elapsed.
    function checkTimeView(bytes32 pointer) external view returns (bool);

    // =========================
    // Setters
    // =========================

    /// @dev Sets the time period before checks.
    /// @param timePeriod The time period to set in seconds.
    /// @param pointer The bytes32 pointer value.
    function setTimePeriod(uint64 timePeriod, bytes32 pointer) external;

    // =========================
    // Getters
    // =========================

    /// @notice Retrieves the local time checker storage values.
    /// @param pointer The bytes32 pointer value.
    /// @return lastActionTime The last recorded action time.
    /// @return timePeriod The set time period in seconds.
    /// @return initialized A boolean indicating if the contract has been initialized or not.
    function getLocalTimeCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (uint256 lastActionTime, uint256 timePeriod, bool initialized);
}

