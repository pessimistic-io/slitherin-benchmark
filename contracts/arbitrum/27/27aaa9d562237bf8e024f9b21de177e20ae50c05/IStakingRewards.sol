// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IStakingRewards {
  function claimRewardsFor(
    uint32,
    uint32,
    address,
    address
  ) external;
}

