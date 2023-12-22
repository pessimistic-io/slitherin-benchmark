// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXRewardReader {
  function getStakingInfo(address _account, address[] memory _rewardTrackers) external view returns (uint256[] memory);
}

