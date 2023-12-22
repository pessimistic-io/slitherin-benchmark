//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct Addresses {
    address feeStrategy;
    address stakingStrategy;
    address optionPricing;
    address priceOracle;
    address volatilityOracle;
    address feeDistributor;
    address optionsTokenImplementation;
}

struct EpochData {
    bool expired;
    uint256 startTime;
    uint256 expiry;
    uint256 settlementPrice;
    uint256 totalCollateralBalance; // Premium + Deposits from all strikes
    uint256 collateralExchangeRate; // Exchange rate for collateral to underlying (Only applicable to CALL options)
    uint256 settlementCollateralExchangeRate; // Exchange rate for collateral to underlying on settlement (Only applicable to CALL options)
    uint256[] strikes;
    uint256[] totalRewardsCollected;
    uint256[] rewardDistributionRatios;
    address[] rewardTokensToDistribute;
}

struct EpochStrikeData {
    address strikeToken;
    uint256 totalCollateral;
    uint256 activeCollateral;
    uint256 totalPremiums;
    uint256 checkpointPointer;
    uint256[] rewardStoredForPremiums;
    uint256[] rewardDistributionRatiosForPremiums;
}

struct VaultCheckpoint {
    uint256 activeCollateral;
    uint256 totalCollateral;
    uint256 accruedPremium;
}

struct WritePosition {
    uint256 epoch;
    uint256 strike;
    uint256 collateralAmount;
    uint256 checkpointIndex;
    uint256[] rewardDistributionRatios;
}

