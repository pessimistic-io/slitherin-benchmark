// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

struct DistributionRewards {
	address rewardToken;
	uint256 totalRewardIssued;
	uint256 lastUpdateTime;
	uint256 totalRewardSupply;
	uint256 rewardDistributionPerMin;
}


