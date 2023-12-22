// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import { TokenTransferrer } from "./TokenTransferrer.sol";
import "./VestaMath.sol";
import "./BaseVesta.sol";
import "./StakingFarmModel.sol";
import "./IMultiRewardsStaking.sol";
import "./StakeToken.sol";

contract MultiRewardsStaking is IMultiRewardsStaking, TokenTransferrer, BaseVesta {
	address public depositToken;
	StakeToken public stakeToken;

	// user -> reward token -> amount
	mapping(address => mapping(address => uint256)) private userRewardPerTokenPaid;
	mapping(address => mapping(address => uint256)) private rewards;
	mapping(address => Reward) private rewardData;
	mapping(address => bool) private isRewardAssetLookup;
	address[] public rewardTokens;

	mapping(address => uint256) private stakedAmount;
	uint256 public totalStakedAmount;

	modifier updateReward(address _account) {
		_updateReward(_account);
		_;
	}

	function _updateReward(address _account) internal {
		uint256 rewardTokensLength = rewardTokens.length;
		address token;
		for (uint256 i; i < rewardTokensLength; ++i) {
			token = rewardTokens[i];
			rewardData[token].rewardPerTokenStored = rewardPerToken(token);
			rewardData[token].lastUpdateTime = uint128(getLastTimeRewardApplicable(token));
			if (_account != address(0)) {
				rewards[_account][token] = earned(_account, token);
				userRewardPerTokenPaid[_account][token] = rewardData[token]
					.rewardPerTokenStored;
			}
		}
	}

	modifier ensureIsNotDepositToken(address _token) {
		if (_token == depositToken) revert IsAlreadyDepositToken();
		_;
	}

	modifier ensureIsNotRewardAsset(address _token) {
		if (isRewardAssetLookup[_token]) revert IsAlreadyRewardAsset();
		_;
	}

	modifier ensureIsRewardAsset(address _token) {
		if (!isRewardAssetLookup[_token]) revert IsNotRewardAsset();
		_;
	}

	function setUp(
		string calldata _name,
		string calldata _symbol,
		address _depositToken
	) external initializer {
		__BASE_VESTA_INIT();
		stakeToken = new StakeToken(_name, _symbol);
		depositToken = _depositToken;
	}

	function stake(uint256 _amount)
		external
		override
		notZero(_amount)
		updateReward(msg.sender)
	{
		stakedAmount[msg.sender] += _amount;

		totalStakedAmount += _amount;

		_performTokenTransferFrom(
			depositToken,
			msg.sender,
			address(this),
			_amount,
			false
		);

		stakeToken.mint(msg.sender, _amount);

		emit Staked(msg.sender, _amount);
	}

	function withdraw(uint256 _amount)
		public
		override
		nonReentrant
		notZero(_amount)
		updateReward(msg.sender)
	{
		stakedAmount[msg.sender] -= _amount;

		totalStakedAmount -= _amount;

		stakeToken.burn(msg.sender, _amount);

		_performTokenTransfer(depositToken, msg.sender, _amount, false);

		emit Withdrawn(msg.sender, _amount);
	}

	function claimRewards() public override nonReentrant updateReward(msg.sender) {
		uint256 rewardTokensLength = rewardTokens.length;
		address rewardsToken;
		uint256 reward;
		for (uint256 i; i < rewardTokensLength; ++i) {
			rewardsToken = rewardTokens[i];
			reward = rewards[msg.sender][rewardsToken];
			if (reward > 0) {
				rewards[msg.sender][rewardsToken] = 0;
				_performTokenTransfer(rewardsToken, msg.sender, reward, false);
				emit RewardPaid(msg.sender, rewardsToken, reward);
			}
		}
	}

	function exit() external override {
		withdraw(stakedAmount[msg.sender]);
		claimRewards();
	}

	function addReward(address _rewardsToken, uint128 _rewardsDuration)
		public
		onlyOwner
		ensureIsNotRewardAsset(_rewardsToken)
	{
		rewardTokens.push(_rewardsToken);
		rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;
		isRewardAssetLookup[_rewardsToken] = true;
	}

	function notifyRewardAmount(address _rewardsToken, uint128 reward)
		external
		onlyOwner
		ensureIsRewardAsset(_rewardsToken)
		updateReward(address(0))
	{
		_performTokenTransferFrom(
			_rewardsToken,
			msg.sender,
			address(this),
			reward,
			false
		);

		Reward storage userRewardData = rewardData[_rewardsToken];

		if (block.timestamp >= userRewardData.periodFinish) {
			userRewardData.rewardRate = reward / userRewardData.rewardsDuration;
		} else {
			uint128 remaining = userRewardData.periodFinish - uint128(block.timestamp);
			uint128 leftover = remaining * userRewardData.rewardRate;
			userRewardData.rewardRate =
				(reward + leftover) /
				userRewardData.rewardsDuration;
		}

		userRewardData.lastUpdateTime = uint128(block.timestamp);
		userRewardData.periodFinish =
			uint128(block.timestamp) +
			userRewardData.rewardsDuration;

		emit RewardAdded(reward);
	}

	function recoverERC20(address _tokenAddress, uint256 _tokenAmount)
		external
		onlyOwner
		ensureIsNotRewardAsset(_tokenAddress)
		ensureIsNotDepositToken(_tokenAddress)
	{
		_performTokenTransfer(_tokenAddress, msg.sender, _tokenAmount, false);

		emit Recovered(_tokenAddress, _tokenAmount);
	}

	function setRewardsDuration(address _rewardsToken, uint128 _rewardsDuration)
		external
		notZero(_rewardsDuration)
		onlyOwner
	{
		Reward storage userRewardData = rewardData[_rewardsToken];

		if (block.timestamp <= userRewardData.periodFinish)
			revert RewardPeriodStillActive();

		userRewardData.rewardsDuration = _rewardsDuration;

		emit RewardsDurationUpdated(_rewardsToken, _rewardsDuration);
	}

	function getStakedAmount(address _account)
		external
		view
		override
		returns (uint256)
	{
		return stakedAmount[_account];
	}

	function isRewardAsset(address _tokenAddress)
		external
		view
		override
		returns (bool)
	{
		return isRewardAssetLookup[_tokenAddress];
	}

	function getRewardData(address _tokenAddress)
		external
		view
		override
		returns (Reward memory)
	{
		return rewardData[_tokenAddress];
	}

	function getUserRewards(address _user, address _tokenAddress)
		external
		view
		override
		returns (uint256)
	{
		return rewards[_user][_tokenAddress];
	}

	function getLastTimeRewardApplicable(address _rewardsToken)
		public
		view
		override
		returns (uint256)
	{
		return VestaMath.min(block.timestamp, rewardData[_rewardsToken].periodFinish);
	}

	function rewardPerToken(address _rewardsToken)
		public
		view
		override
		returns (uint256)
	{
		uint256 currentTotalSupply = totalStakedAmount;
		Reward memory tokenRewardData = rewardData[_rewardsToken];

		if (currentTotalSupply == 0) {
			return tokenRewardData.rewardPerTokenStored;
		}

		return
			tokenRewardData.rewardPerTokenStored +
			(((getLastTimeRewardApplicable(_rewardsToken) -
				tokenRewardData.lastUpdateTime) *
				tokenRewardData.rewardRate *
				1 ether) / currentTotalSupply);
	}

	function earned(address _account, address _rewardsToken)
		public
		view
		override
		returns (uint256)
	{
		return
			// prettier-ignore
			(rewardPerToken(_rewardsToken) - userRewardPerTokenPaid[_account][_rewardsToken]) 
			* stakedAmount[_account] 
			/ 1 ether 
			+ rewards[_account][_rewardsToken];
	}

	function getRewardForDuration(address _rewardsToken)
		external
		view
		override
		returns (uint256)
	{
		Reward memory userRewardData = rewardData[_rewardsToken];
		return userRewardData.rewardRate * userRewardData.rewardsDuration;
	}
}

