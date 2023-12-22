// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

struct Reward {
	uint128 rewardsDuration;
	uint128 periodFinish;
	uint128 rewardRate;
	uint128 lastUpdateTime;
	uint256 rewardPerTokenStored;
}


