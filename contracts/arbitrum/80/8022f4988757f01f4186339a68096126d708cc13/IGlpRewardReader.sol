// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IGlpRewardReader {
  function getDepositBalances(
    address _account,
    address[] memory _depositTokens,
    address[] memory _rewardTrackers
  ) external view returns (uint256[] memory);

  function getStakingInfo(
    address _account,
    address[] memory _rewardTrackers
  ) external view returns (uint256[] memory);
}

