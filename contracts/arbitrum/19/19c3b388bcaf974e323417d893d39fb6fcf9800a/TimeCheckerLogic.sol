// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseContract} from "./BaseContract.sol";

import {ITimeCheckerLogic} from "./ITimeCheckerLogic.sol";

/// @title TimeCheckerLogic
contract TimeCheckerLogic is ITimeCheckerLogic, BaseContract {
    // =========================
    // Storage
    // =========================

    /// @dev Fetches the checker storage without initialization check.
    /// @dev Uses inline assembly to point to the specific storage slot.
    /// Be cautious while using this.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for TimeCheckerStorage structure.
    function _getStorageUnsafe(
        bytes32 pointer
    ) internal pure returns (TimeCheckerStorage storage s) {
        assembly ("memory-safe") {
            s.slot := pointer
        }
    }

    /// @dev Fetches the checker storage after checking initialization.
    /// @dev Reverts if the strategy is not initialized.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for TimeCheckerStorage structure.
    function _getStorage(
        bytes32 pointer
    ) internal view returns (TimeCheckerStorage storage s) {
        s = _getStorageUnsafe(pointer);

        if (!s.initialized) {
            revert TimeChecker_NotInitialized();
        }
    }

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc ITimeCheckerLogic
    function timeCheckerInitialize(
        uint64 lastActionTime,
        uint64 timePeriod,
        bytes32 pointer
    ) external onlyVaultItself {
        TimeCheckerStorage storage s = _getStorageUnsafe(pointer);

        if (s.initialized) {
            revert TimeChecker_AlreadyInitialized();
        }
        s.initialized = true;

        s.lastActionTime = lastActionTime;
        s.timePeriod = timePeriod;

        emit TimeCheckerInitialized();
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc ITimeCheckerLogic
    function checkTime(
        bytes32 pointer
    ) external onlyVaultItself returns (bool) {
        TimeCheckerStorage storage s = _getStorage(pointer);

        bool enoughTimePassed = _enoughTimePassed(
            s.lastActionTime,
            s.timePeriod
        );

        if (enoughTimePassed) {
            s.lastActionTime = uint64(block.timestamp);
        }

        return enoughTimePassed;
    }

    /// @inheritdoc ITimeCheckerLogic
    function checkTimeView(bytes32 pointer) external view returns (bool) {
        TimeCheckerStorage storage s = _getStorage(pointer);
        return _enoughTimePassed(s.lastActionTime, s.timePeriod);
    }

    // =========================
    // Setters
    // =========================

    /// @inheritdoc ITimeCheckerLogic
    function setTimePeriod(
        uint64 timePeriod,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _getStorage(pointer).timePeriod = timePeriod;
        emit TimeCheckerSetNewPeriod(timePeriod);
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc ITimeCheckerLogic
    function getLocalTimeCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (uint256 lastActionTime, uint256 timePeriod, bool initialized)
    {
        TimeCheckerStorage storage s = _getStorageUnsafe(pointer);

        return (s.lastActionTime, s.timePeriod, s.initialized);
    }

    // =========================
    // Internal functions
    // =========================

    /// @dev Checks if enough time has passed since the last action.
    /// @param startTime The start time of the last action.
    /// @param period The time period.
    /// @return True if enough time has passed.
    function _enoughTimePassed(
        uint256 startTime,
        uint256 period
    ) internal view returns (bool) {
        return block.timestamp >= (startTime + period);
    }
}

