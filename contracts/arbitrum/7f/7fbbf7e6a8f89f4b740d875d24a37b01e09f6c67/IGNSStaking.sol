// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @custom:version 6.4.1
 */
interface IGNSStaking {
    struct Staker {
        uint128 stakedGns; // 1e18
        uint128 debtDai; // 1e18
    }

    struct UnlockSchedule {
        uint128 totalGns; // 1e18
        uint128 claimedGns; // 1e18
        uint128 debtDai; // 1e18
        uint48 start; // block.timestamp (seconds)
        uint48 duration; // in seconds
        bool revocable;
        UnlockType unlockType;
        uint16 __placeholder;
    }

    struct UnlockScheduleInput {
        uint128 totalGns; // 1e18
        uint48 start; // block.timestamp (seconds)
        uint48 duration; // in seconds
        bool revocable;
        UnlockType unlockType;
    }

    enum UnlockType {
        LINEAR,
        CLIFF
    }

    function owner() external view returns (address);

    function distributeRewardDai(uint256 _amountDai) external;

    function createUnlockSchedule(UnlockScheduleInput calldata _schedule, address _staker) external;

    event UnlockManagerUpdated(address indexed manager, bool authorized);

    event DaiDistributed(uint256 amountDai);
    event DaiHarvested(address indexed staker, uint128 amountDai);
    event DaiHarvestedFromUnlock(address indexed staker, uint256[] ids, uint128 amountDai);

    event GnsStaked(address indexed staker, uint128 amountGns);
    event GnsUnstaked(address indexed staker, uint128 amountGns);
    event GnsClaimed(address indexed staker, uint256[] ids, uint128 amountGns);

    event UnlockScheduled(address indexed staker, uint256 indexed index, UnlockSchedule schedule);
    event UnlockScheduleRevoked(address indexed staker, uint256 indexed index);
}

