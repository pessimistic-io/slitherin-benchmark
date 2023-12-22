// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { StakingRewardsV3 } from "./StakingRewardsV3.sol";

contract RdpxEthLpFarm is StakingRewardsV3 {
  constructor()
    StakingRewardsV3(
      0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55, // rewardToken: DPX
      0x7418F5A2621E13c05d1EFBd71ec922070794b90a, // stakingToken: RDPX/WETH SLP
      86400 * 30, // Reward Duration: 1 Month
      0, // Boost Duration
      0 // Boost
    )
  {}
}

