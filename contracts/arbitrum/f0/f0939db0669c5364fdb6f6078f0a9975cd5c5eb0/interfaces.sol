// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IveSPA {
  function getLastUserSlope(address addr) external view returns (int128);

  function getUserPointHistoryTS(address addr, uint256 idx) external view returns (uint256);

  function userPointEpoch(address addr) external view returns (uint256);

  function checkpoint() external;

  function lockedEnd(address addr) external view returns (uint256);

  function depositFor(address addr, uint128 value) external;

  function createLock(
    uint128 value,
    uint256 unlockTime,
    bool autoCooldown
  ) external;

  function increaseAmount(uint128 value) external;

  function increaseUnlockTime(uint256 unlockTime) external;

  function initiateCooldown() external;

  function withdraw() external;

  function balanceOf(address addr, uint256 ts) external view returns (uint256);

  function balanceOf(address addr) external view returns (uint256);

  function balanceOfAt(address, uint256 blockNumber) external view returns (uint256);

  function totalSupply(uint256 ts) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function totalSupplyAt(uint256 blockNumber) external view returns (uint256);
}

interface IRewardDistributor_v2 {
  function checkpointReward() external;

  function computeRewards(address addr)
    external
    view
    returns (
      uint256, // total rewards earned by user
      uint256, // lastRewardCollectionTime
      uint256 // rewardsTill
    );

  function claim(bool restake) external returns (uint256);
}

interface IStaker {
  function stake(uint256) external;

  function release() external;

  function claimFees(
    address _distroContract,
    address _token,
    address _claimTo
  ) external returns (uint256);
}

interface IFeeClaimer {
  function pendingRewards() external view returns (uint256 pendingRewardsLessFee, uint256 protocolFee);

  function harvest() external;
}

