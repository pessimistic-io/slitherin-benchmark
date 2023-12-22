// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

/// @notice For future upgrades, do not change ClearingHouseStorageV1. Create a new
/// contract which implements ClearingHouseStorageV1 and following the naming convention
/// ClearingHouseStorageVX.
abstract contract ClearingHouseStorage {
    // --------- IMMUTABLE ---------
    address internal _quoteToken;
    address internal _uniswapV3Factory;

    // cache the settlement token's decimals for gas optimization
    uint8 internal _settlementTokenDecimals;
    // --------- ^^^^^^^^^ ---------

    address internal _clearingHouseConfig;
    address internal _vault;
    address internal _vPool;
    address internal __orderBook;
    address internal _accountBalance;
    address internal _marketRegistry;
    address internal _insuranceFund;
    address internal _platformFund;
    address internal _maker;
    address internal _rewardMiner;

    address internal _delegateApproval;

    // sub 1 when use
    address[10] private __gap1;
    // sub 1 when use
    uint256[10] private __gap2;
}

