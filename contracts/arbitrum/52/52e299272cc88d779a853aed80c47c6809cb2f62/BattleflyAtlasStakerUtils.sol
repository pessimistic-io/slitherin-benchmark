// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAtlasMine.sol";

library BattleflyAtlasStakerUtils {
    /**
     * @dev Get lock period
     *      Need to consider about adding 1 more day to lock period regarding the daily cron job
     */
    function getLockPeriod(IAtlasMine.Lock _lock, IAtlasMine ATLAS_MINE) external pure returns (uint64) {
        if (_lock == IAtlasMine.Lock.twoWeeks) {
            return 14 days + 1 days + uint64(ATLAS_MINE.getVestingTime(_lock));
        }
        if (_lock == IAtlasMine.Lock.oneMonth) {
            return 30 days + 1 days + uint64(ATLAS_MINE.getVestingTime(_lock));
        }
        if (_lock == IAtlasMine.Lock.threeMonths) {
            return 90 days + 1 days + uint64(ATLAS_MINE.getVestingTime(_lock));
        }
        if (_lock == IAtlasMine.Lock.sixMonths) {
            return 180 days + 1 days + uint64(ATLAS_MINE.getVestingTime(_lock));
        }
        if (_lock == IAtlasMine.Lock.twelveMonths) {
            return 365 days + 1 days + uint64(ATLAS_MINE.getVestingTime(_lock));
        }

        revert("BattleflyAtlasStaker: Invalid Lock");
    }
}

