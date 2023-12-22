//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

struct Addresses {
  address quoteToken;
  address baseToken;
  address feeDistributor;
  address feeStrategy;
  address optionPricing;
  address priceOracle;
  address volatilityOracle;
}

struct VaultState {
  // Settlement price set on expiry
  uint256 settlementPrice;
  // Timestamp at which the epoch expires
  uint256 expiryTime;
  // Start timestamp of the epoch
  uint256 startTime;
  // Whether vault has been bootstrapped
  bool isVaultReady;
  // Whether vault is expired
  bool isVaultExpired;
}


struct Checkpoint {
  uint256 startTime;
  uint256 totalLiquidity;
  uint256 totalLiquidityBalance;
  uint256 activeCollateral;
  uint256 unlockedCollateral;
  uint256 premiumAccrued;
  uint256 fundingFeesAccrued;
  uint256 underlyingAccrued;
}

struct OptionsPurchase {
  uint256 epoch;
  uint256 optionStrike;
  uint256 optionsAmount;
  uint256[] strikes;
  uint256[] checkpoints;
  uint256[] weights;
  address user;
  bool unlock;
}

struct DepositPosition {
  uint256 epoch;
  uint256 strike;
  uint256 timestamp;
  uint256 liquidity;
  uint256 checkpoint;
  address depositor;
}

