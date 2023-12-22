// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

/// @notice For future upgrades, do not change PNFTTokenStorageV1. Create a new
/// contract which implements PNFTTokenStorageV1 and following the naming convention
/// PNFTTokenStorageVX.
abstract contract PNFTTokenStorageV1 {
    // --------- IMMUTABLE ---------

    struct VestingScheduleParams {
        address beneficiary;
        uint256 start;
        uint256 cliff;
        uint256 duration;
        uint256 slicePeriodSeconds;
        bool revocable;
        uint256 unvestingAmount;
        uint256 amount;
    }

    struct VestingSchedule {
        bool initialized;
        // beneficiary of tokens after they are released
        address beneficiary;
        // cliff period in seconds
        uint256 cliff;
        // start time of the vesting period
        uint256 start;
        // duration of the vesting period in seconds
        uint256 duration;
        // duration of a slice period for the vesting in seconds
        uint256 slicePeriodSeconds;
        // whether or not the vesting is revocable
        bool revocable;
        // total amount of tokens to be released at the end of the vesting
        uint256 amountTotal;
        // amount of tokens released
        uint256 released;
        // whether or not the vesting has been revoked
        bool revoked;
    }

    // address of the ERC20 token
    bytes32[] internal _vestingSchedulesIds;
    mapping(bytes32 => VestingSchedule) internal _vestingSchedules;
    uint256 internal _vestingSchedulesTotalAmount;
    mapping(address => uint256) internal _holdersVestingCount;

    address[10] private __gap1;
    uint256[10] private __gap2;
}

