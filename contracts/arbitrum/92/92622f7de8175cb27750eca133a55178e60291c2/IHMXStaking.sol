// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IHMXStaking {
  /**
   * Structs
   */
  struct LockedReward {
    address account;
    address reward;
    uint256 amount;
    uint256 endRewardLockTimestamp;
  }

  function userTokenAmount(address stakingToken, address user)
    external
    returns (uint256 amount);

  function userLockedRewardsStartIndex(address user)
    external
    returns (uint256 index);

  function addStakingToken(
    address newStakingToken,
    address[] memory newRewarders
  ) external;

  function addRewarder(address newRewarder, address[] memory newStakingToken)
    external;

  function removeRewarderFoStakingTokenByIndex(
    uint256 removeRewarderIndex,
    address stakingToken
  ) external;

  function deposit(address account, address token, uint256 amount) external;

  function withdraw(address stakingToken, uint256 amount) external;

  function harvest(address[] memory rewarders) external;

  function harvestToCompounder(address user, address[] memory _rewarders)
    external;

  function claimLockedReward(address user) external;

  function calculateShare(address rewarder, address user)
    external
    view
    returns (uint256);

  function calculateTotalShare(address rewarder)
    external
    view
    returns (uint256);

  function setRewards(address[] memory _allRewarders) external;

  function getUserTokenAmount(address stakingToken, address account)
    external
    view
    returns (uint256);

  function getUserLockedRewards(address account)
    external
    view
    returns (LockedReward[] memory);

  function getStakingTokenRewarders(address stakingToken)
    external
    view
    returns (address[] memory);

  function getAccumulatedLockedReward(
    address user,
    address[] memory rewards,
    bool isOnlyClaimAble
  ) external view returns (address[] memory, uint256[] memory);
}

