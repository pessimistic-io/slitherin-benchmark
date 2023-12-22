// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import { TokenTransferrer } from "./TokenTransferrer.sol";
import "./VestaMath.sol";
import "./BaseVesta.sol";
import "./StakingFarmModel.sol";
import "./IVstaStakingFarm.sol";
import "./StakeToken.sol";

contract VstaStakingFarm is IVstaStakingFarm, TokenTransferrer, BaseVesta {
	// user -> deposit token -> amount
	mapping(address => mapping(address => uint256)) private depositBalances;
	mapping(address => bool) private isDepositTokenLookup;
	address[] public depositTokens;
	address public esVSTA;

	// user -> reward token -> amount
	mapping(address => mapping(address => uint256)) private userRewardPerTokenPaid;
	mapping(address => mapping(address => uint256)) private rewards;
	mapping(address => Reward) private rewardData;
	mapping(address => bool) private isRewardAssetLookup;
	address[] public rewardTokens;

	mapping(address => uint256) private stakedAmount;
	uint256 public totalStakedAmount;
	StakeToken public stakeToken;

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
		if (isDepositTokenLookup[_token]) revert IsAlreadyDepositToken();
		_;
	}

	modifier ensureIsNotRewardAsset(address _token) {
		if (isRewardAssetLookup[_token]) revert IsAlreadyRewardAsset();
		_;
	}

	modifier ensureIsDepositToken(address _token) {
		if (!isDepositTokenLookup[_token]) revert IsNotDepositToken();
		_;
	}

	modifier ensureIsRewardAsset(address _token) {
		if (!isRewardAssetLookup[_token]) revert IsNotRewardAsset();
		_;
	}

	function setUp(
		string calldata _name,
		string calldata _symbol,
		address _esVSTA
	) external initializer {
		__BASE_VESTA_INIT();
		stakeToken = new StakeToken(_name, _symbol);
		esVSTA = _esVSTA;

		depositTokens.push(_esVSTA);
		isDepositTokenLookup[_esVSTA] = true;
	}

	function stake(address _depositToken, uint256 _amount)
		external
		override
		notZero(_amount)
		ensureIsDepositToken(_depositToken)
		updateReward(msg.sender)
	{
		stakedAmount[msg.sender] += _amount;
		depositBalances[msg.sender][_depositToken] += _amount;
		totalStakedAmount += _amount;

		_performTokenTransferFrom(
			_depositToken,
			msg.sender,
			address(this),
			_amount,
			false
		);

		if (_depositToken == esVSTA) stakeToken.mint(msg.sender, _amount);

		emit Staked(msg.sender, _depositToken, _amount);
	}

	function withdraw(address _depositToken, uint256 _amount)
		public
		override
		nonReentrant
		notZero(_amount)
		ensureIsDepositToken(_depositToken)
		updateReward(msg.sender)
	{
		stakedAmount[msg.sender] -= _amount;
		depositBalances[msg.sender][_depositToken] -= _amount;
		totalStakedAmount -= _amount;

		if (_depositToken == esVSTA) stakeToken.burn(msg.sender, _amount);

		_performTokenTransfer(_depositToken, msg.sender, _amount, false);

		emit Withdrawn(msg.sender, _depositToken, _amount);
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
		claimRewards();

		stakedAmount[msg.sender] = 0;

		uint256 depositTokensLength = depositTokens.length;
		address currentDepositToken;
		uint256 currentAmount;
		for (uint256 i; i < depositTokensLength; ++i) {
			currentDepositToken = depositTokens[i];
			currentAmount = depositBalances[msg.sender][currentDepositToken];

			if (currentAmount > 0) {
				if (currentDepositToken == esVSTA)
					stakeToken.burn(msg.sender, currentAmount);

				depositBalances[msg.sender][currentDepositToken] = 0;
				_performTokenTransfer(currentDepositToken, msg.sender, currentAmount, false);
				emit Withdrawn(msg.sender, currentDepositToken, currentAmount);
			}
		}
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

	function addDepositToken(address _depositToken)
		external
		onlyOwner
		ensureIsNotDepositToken(_depositToken)
	{
		depositTokens.push(_depositToken);
		isDepositTokenLookup[_depositToken] = true;
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
		ensureIsNotDepositToken(_tokenAddress)
		ensureIsNotRewardAsset(_tokenAddress)
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

	function isDepositToken(address _tokenAddress)
		external
		view
		override
		returns (bool)
	{
		return isDepositTokenLookup[_tokenAddress];
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

	function getDepositBalance(address _user, address _tokenAddress)
		external
		view
		override
		returns (uint256)
	{
		return depositBalances[_user][_tokenAddress];
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
		uint256 currentTotalStaked = totalStakedAmount;
		Reward memory tokenRewardData = rewardData[_rewardsToken];

		if (currentTotalStaked == 0) {
			return tokenRewardData.rewardPerTokenStored;
		}

		return
			tokenRewardData.rewardPerTokenStored +
			(((getLastTimeRewardApplicable(_rewardsToken) -
				tokenRewardData.lastUpdateTime) *
				tokenRewardData.rewardRate *
				1 ether) / currentTotalStaked);
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


