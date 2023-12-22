// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

/// @notice Percent complete schedule.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/libraries/CompletionSchedule.sol)
/// @dev Assumes percentages are increasing and have ether decimals.
library CompletionSchedule {
    struct Schedule {
        // monotonically increasing timestamps
        uint256[] times;
        // monotonically increasing percentage values
        uint256[] percentages;
    }

    error CompletionSchedule__EmptyArray();
    error CompletionSchedule__NoArrayParity();
    error CompletionSchedule__IncompleteData();
    error CompletionSchedule__NotMonotonicIncreasing();

    function verifySchedule(Schedule memory schedule) internal pure {
        if (schedule.percentages.length == 0 || schedule.times.length == 0) revert CompletionSchedule__EmptyArray();
        if (schedule.percentages.length != schedule.times.length) revert CompletionSchedule__NoArrayParity();
        if (schedule.percentages[schedule.percentages.length - 1] != 100 ether)
            revert CompletionSchedule__IncompleteData();

        for (uint256 i = 0; i < schedule.percentages.length - 1; i++) {
            if (schedule.times[i] >= schedule.times[i + 1]) revert CompletionSchedule__NotMonotonicIncreasing();
            if (schedule.percentages[i] >= schedule.percentages[i + 1])
                revert CompletionSchedule__NotMonotonicIncreasing();
        }
    }

    function percentageAt(Schedule memory schedule, uint256 time) internal pure returns (uint256) {
        uint256 percentage = 100 ether;
        for (uint256 i = 0; i < schedule.times.length; i++) {
            if (schedule.times[i] > time) {
                percentage = i == 0 ? 0 : schedule.percentages[i - 1];
                break;
            }
        }
        return percentage;
    }
}

