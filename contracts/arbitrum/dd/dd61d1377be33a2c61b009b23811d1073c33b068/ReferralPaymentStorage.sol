// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

/// @notice For future upgrades, do not change InsuranceFundStorageV1. Create a new
/// contract which implements InsuranceFundStorageV1 and following the naming convention
/// InsuranceFundStorageVX.
abstract contract ReferralPaymentStorage {
    // --------- IMMUTABLE ---------

    address internal _pnftToken;
    address internal _admin;
    mapping(address => uint256) public _lastPNFTPayments;
    mapping(address => uint256) public _lastETHPayments;

    address[10] private __gap1;
    uint256[10] private __gap2;
}

