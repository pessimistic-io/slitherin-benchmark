// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

library DistributionTypes {
  struct RewardsConfigInput {
    uint88 emissionPerSecond;
    uint256 totalSupply;
    uint32 distributionEnd;
    address asset;
    address reward;
  }

  struct UserAssetInput {
    address underlyingAsset;
    uint256 userBalance;
    uint256 totalSupply;
  }
}

