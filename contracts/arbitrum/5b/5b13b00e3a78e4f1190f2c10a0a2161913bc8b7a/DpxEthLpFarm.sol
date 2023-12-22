// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { StakingRewardsV3 } from "./StakingRewardsV3.sol";

contract DpxEthLpFarm is StakingRewardsV3 {
  constructor()
    StakingRewardsV3(
      0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55, // rewardToken: DPX
      0x0C1Cf6883efA1B496B01f654E247B9b419873054, // stakingToken: DPX/WETH SLP
      86400 * 30, // 1 Month
      0, // Boost Duration
      0 // Boost
    )
  {}
}

