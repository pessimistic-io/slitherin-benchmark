// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "./StakingFarmModel.sol";

interface IMultiRewardsStaking {
	error IsAlreadyDepositToken();
	error IsAlreadyRewardAsset();
	error IsNotRewardAsset();
	error RewardPeriodStillActive();

	event RewardAdded(uint256 _reward);
	event Staked(address indexed _user, uint256 _amount);
	event Withdrawn(address indexed _user, uint256 _amount);
	event RewardPaid(
		address indexed _user,
		address indexed _rewardsToken,
		uint256 _reward
	);
	event RewardsDurationUpdated(address _token, uint256 _newDuration);
	event Recovered(address _token, uint256 _amount);

	function stake(uint256 _amount) external;

	function withdraw(uint256 _amount) external;

	function claimRewards() external;

	function exit() external;

	function getStakedAmount(address account) external view returns (uint256);

	function isRewardAsset(address _tokenAddress) external view returns (bool);

	function getRewardData(address _tokenAddress)
		external
		view
		returns (Reward memory);

	function getUserRewards(address _user, address _tokenAddress)
		external
		view
		returns (uint256);

	function getLastTimeRewardApplicable(address _rewardsToken)
		external
		view
		returns (uint256);

	function rewardPerToken(address _rewardsToken) external view returns (uint256);

	function earned(address account, address _rewardsToken)
		external
		view
		returns (uint256);

	function getRewardForDuration(address _rewardsToken)
		external
		view
		returns (uint256);
}


