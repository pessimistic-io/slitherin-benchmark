// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IPlutusEpochStakingV2 {
  struct StakedDetails {
    uint112 amount;
    uint32 lastCheckpoint;
  }

  struct EpochCheckpoint {
    uint32 startedAt;
    uint32 endedAt;
    uint112 totalStaked;
  }

  function currentEpoch() external view returns (uint32);

  function currentEpochStartedAt() external view returns (uint32);

  function epochCheckpoints(
    uint32 _epoch
  ) external view returns (uint32 startedAt, uint32 endedAt, uint112 totalStaked);

  function stakedDetails(
    address _user
  ) external view returns (uint112 amount, uint32 lastCheckpoint);

  function stakedCheckpoints(
    address _user,
    uint32 _epoch
  ) external view returns (uint112 _amountStaked);

  function currentTotalStaked() external view returns (uint112);

  function advanceEpoch() external;

  function setWhitelist(address) external;

  function setPause(bool _isPaused) external;

  function stakingWindowOpen() external view returns (bool);
  
  event AdvanceEpoch();
  event Staked(address indexed _from, uint112 _amt, uint32 _epoch);
  event Unstaked(address indexed _from, uint112 _amt, uint32 _epoch);
}

