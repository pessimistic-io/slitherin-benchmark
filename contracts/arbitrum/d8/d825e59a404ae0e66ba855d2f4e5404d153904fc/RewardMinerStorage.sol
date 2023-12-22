// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

/// @notice For future upgrades, do not change InsuranceFundStorageV1. Create a new
/// contract which implements InsuranceFundStorageV1 and following the naming convention
/// InsuranceFundStorageVX.
abstract contract RewardMinerStorage {
    // --------- IMMUTABLE ---------

    struct PeriodConfig {
        uint256 start;
        uint256 end;
        uint256 total;
    }

    struct PeriodData {
        uint256 periodNumber;
        mapping(address => uint256) users;
        uint256 amount;
        uint256 total;
        mapping(address => int256) pnlUsers;
        int256 pnlAmount;
    }
    //
    address internal _clearingHouse;
    address internal _pnftToken;
    uint256 internal _start;
    uint256 internal _periodDuration;
    uint256 internal _limitClaimPeriod;
    PeriodConfig[] public _periodConfigs;
    //
    mapping(uint256 => PeriodData) public _periodDataMap;
    uint256[] public _periodNumbers;
    uint256 internal _allocation;
    uint256 internal _spend;
    mapping(address => uint256) public _lastClaimPeriodNumberMap;
    mapping(address => uint256) public _userAmountMap;
    mapping(address => uint256) public _userSpendMap;

    address[10] private __gap1;

    uint256 internal _startPnlNumber;
    uint256 internal _pnlRatio;

    uint256[8] private __gap2;
}

