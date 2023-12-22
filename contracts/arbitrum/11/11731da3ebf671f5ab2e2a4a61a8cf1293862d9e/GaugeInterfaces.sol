// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ISpaStakerGaugeHandler {
  struct BribeRewardData {
    address token;
    uint256 amount;
  }

  struct RewardInfo {
    address gauge;
    BribeRewardData[] rewardData;
  }

  function pendingRewards(address _user) external view returns (RewardInfo[] memory rewardInfo);

  function voteForGaugeWeight(address _gAddr, uint256 _userWeight) external;

  function claimAndTransferBribes() external returns (BribeRewardData[] memory rwData);
}

