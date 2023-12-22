// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.17;

interface IRewardReader {
    function getStakingInfo(address _account, address[] memory _rewardTrackers) external view returns (uint256[] memory);
}
