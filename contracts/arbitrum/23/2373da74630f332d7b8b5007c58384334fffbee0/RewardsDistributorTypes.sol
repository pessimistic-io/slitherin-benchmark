// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {ITransferStrategyBase} from "./ITransferStrategyBase.sol";
import {IEACAggregatorProxy} from "./IEACAggregatorProxy.sol";

library RewardsDistributorTypes {
  struct RewardsConfigInput {
    uint88 emissionPerSecond;
    uint256 totalSupply;
    uint32 distributionEnd;
    address asset;
    address reward;
    ITransferStrategyBase transferStrategy;
    IEACAggregatorProxy rewardOracle;
  }

  struct UserAssetStatsInput {
    address underlyingAsset;
    uint256 userBalance;
    uint256 totalSupply;
  }
}

