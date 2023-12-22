//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

/**
 * @title ITokenVesting.
 * @notice This is an interface for token vesting. It includes functionalities for adding vesting schedules and claiming vested tokens.
 */
interface ITokenVesting {
    error InvalidScheduleID();
    error VestingNotStarted();
    error AllTokensClaimed();
    error OnlyVestingManagerAccess();
    error MaxSchedules();

    event VestingAdded(
        address indexed beneficiary,
        uint256 indexed allocationId,
        uint256 startTime,
        uint256 endTime,
        uint256 amount
    );

    event TokenWithdrawn(
        address indexed beneficiary,
        uint256 indexed allocationId,
        uint256 value
    );

    struct Vesting {
        uint256 startTime;
        uint256 endTime;
        uint256 totalAmount;
        uint256 claimedAmount;
    }

    /**
     * @notice Adds a vesting schedule for a beneficiary.
     * @param beneficiary Address of the beneficiary.
     * @param startTime Start time of the vesting schedule.
     * @param duration Duration of the vesting schedule.
     * @param amount Total amount of tokens to be vested.
     */
    function addVesting(
        address beneficiary,
        uint256 startTime,
        uint256 duration,
        uint256 amount
    ) external;

    /**
     * @notice Allows a beneficiary to claim vested tokens.
     * @param scheduleIds Array of identifiers for the vesting schedules.
     */
    function claim(uint256[] calldata scheduleIds) external payable;
}

