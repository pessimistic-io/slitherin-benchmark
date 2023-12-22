// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

/// @notice For future upgrades, do not change InsuranceFundStorageV1. Create a new
/// contract which implements InsuranceFundStorageV1 and following the naming convention
/// InsuranceFundStorageVX.
abstract contract AgentStorage {
    // --------- IMMUTABLE ---------
    address internal _userAccountImpl;
    address internal _userAccountTpl;
    address internal _admin;
    address internal _clearingHouse;
    address internal _vault;
    address internal _accountBalance;
    uint256 internal _txFee;

    mapping(address => address) _userAccountMap;
    mapping(address => mapping(uint256 => bool)) _traderNonceMap;
    mapping(address => int256) _balanceMap;
    //
    uint256 internal _minClaimBalance;
    int256 internal _traderBalance;
}

