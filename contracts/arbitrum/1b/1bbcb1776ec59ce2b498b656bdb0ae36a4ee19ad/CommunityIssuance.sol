// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./BaseVesta.sol";
import { TokenTransferrer } from "./TokenTransferrer.sol";
import "./ICommunityIssuance.sol";
import "./CommunityIssuanceModel.sol";

/**
@title CommunityIssuance
@notice Holds and issues rewards for stability pool. New reward asset types and distribution amounts are also set here.
*/
contract CommunityIssuance is ICommunityIssuance, TokenTransferrer, BaseVesta {
	bytes1 public constant STABILITY_POOL = 0x01;
	uint256 public constant DISTRIBUTION_DURATION = 7 days / 60;
	uint256 public constant SECONDS_IN_ONE_MINUTE = 60;

	address public stabilityPoolAddress;
	mapping(address => DistributionRewards) internal stabilityPoolRewards; // asset -> DistributionRewards
	mapping(address => bool) internal isRewardAssetLookup; // asset -> whether it is a reward asset or not
	address[] internal rewardAssets;

	modifier ensureRewardAsset(address _asset) {
		if (!isRewardAssetLookup[_asset]) revert IsNotRewardAsset();
		_;
	}

	modifier ensureNotRewardAsset(address _asset) {
		if (isRewardAssetLookup[_asset]) revert IsAlreadyRewardAsset();
		_;
	}

	function setUp(address _stabilityPoolAddress)
		external
		initializer
		onlyContract(_stabilityPoolAddress)
	{
		__BASE_VESTA_INIT();

		_setPermission(_stabilityPoolAddress, STABILITY_POOL);

		emit StabilityPoolAddressSet(_stabilityPoolAddress);
	}

	function addRewardAsset(address _asset, uint256 _weeklyReward)
		external
		override
		onlyOwner
		ensureNotRewardAsset(_asset)
	{
		isRewardAssetLookup[_asset] = true;

		rewardAssets.push(_asset);

		stabilityPoolRewards[_asset] = DistributionRewards(
			_asset,
			0,
			0,
			0,
			_weeklyReward / DISTRIBUTION_DURATION
		);

		emit AddRewardAsset(_asset);
	}

	function disableRewardAsset(address _asset)
		external
		override
		onlyOwner
		ensureRewardAsset(_asset)
	{
		stabilityPoolRewards[_asset].lastUpdateTime = 0;
		emit DisableRewardAsset(_asset);
	}

	// FIXME: Not best solution since its very rare an inactive pool will be empty.
	function removeRewardAsset(address _asset)
		external
		override
		onlyOwner
		ensureRewardAsset(_asset)
	{
		if (_balanceOf(_asset, address(this)) > 0) revert BalanceMustBeZero();
		if (stabilityPoolRewards[_asset].lastUpdateTime > 0) revert RewardsStillActive();

		isRewardAssetLookup[_asset] = false;

		uint256 rewardLength = rewardAssets.length;
		for (uint256 i = 0; i < rewardLength; i++) {
			// Delete address from array by swapping with last element and calling pop()
			if (rewardAssets[i] == _asset) {
				rewardAssets[i] = rewardAssets[rewardLength - 1];
				rewardAssets.pop();
				break;
			}
		}

		delete stabilityPoolRewards[_asset];

		emit RemoveRewardAsset(_asset);
	}

	function addFundsToStabilityPool(address _asset, uint256 _amount)
		external
		override
		onlyOwner
		ensureRewardAsset(_asset)
	{
		DistributionRewards storage distributionRewards = stabilityPoolRewards[_asset];

		if (distributionRewards.lastUpdateTime == 0) {
			distributionRewards.lastUpdateTime = block.timestamp;
		}

		distributionRewards.totalRewardSupply += _amount;

		_performTokenTransferFrom(_asset, msg.sender, address(this), _amount, false);

		emit AddFundsToStabilityPool(_asset, _amount);
	}

	function removeFundsFromStabilityPool(address _asset, uint256 _amount)
		external
		override
		onlyOwner
		ensureRewardAsset(_asset)
	{
		DistributionRewards storage distributionRewards = stabilityPoolRewards[_asset];

		if (
			distributionRewards.totalRewardSupply - _amount <
			distributionRewards.totalRewardIssued
		) revert RewardSupplyCannotBeBelowIssued();

		distributionRewards.totalRewardSupply -= _amount;

		_performTokenTransfer(_asset, msg.sender, _amount, false);

		emit RemoveFundsToStabilityPool(_asset, _amount);
	}

	function issueAssets()
		external
		override
		hasPermission(STABILITY_POOL)
		returns (address[] memory assetAddresses_, uint256[] memory issuanceAmounts_)
	{
		uint256 arrayLengthCache = rewardAssets.length;
		assetAddresses_ = new address[](arrayLengthCache);
		issuanceAmounts_ = new uint256[](arrayLengthCache);

		for (uint256 i = 0; i < arrayLengthCache; ++i) {
			assetAddresses_[i] = rewardAssets[i];
			issuanceAmounts_[i] = _issueAsset(assetAddresses_[i]);
		}

		return (assetAddresses_, issuanceAmounts_);
	}

	function _issueAsset(address _asset) internal returns (uint256 issuance_) {
		uint256 totalIssuance;
		(issuance_, totalIssuance) = getLastUpdateIssuance(_asset);

		if (issuance_ == 0) return 0;

		DistributionRewards storage distributionRewards = stabilityPoolRewards[_asset];
		distributionRewards.lastUpdateTime = block.timestamp;
		distributionRewards.totalRewardIssued = totalIssuance;

		emit AssetIssuanceUpdated(_asset, issuance_, totalIssuance, block.timestamp);

		return issuance_;
	}

	function sendAsset(
		address _asset,
		address _account,
		uint256 _amount
	) external override hasPermission(STABILITY_POOL) ensureRewardAsset(_asset) {
		uint256 balance = _balanceOf(_asset, address(this));
		uint256 safeAmount = balance >= _amount ? _amount : balance;

		if (safeAmount == 0) return;

		_performTokenTransfer(_asset, _account, safeAmount, false);
	}

	function setWeeklyAssetDistribution(address _asset, uint256 _weeklyReward)
		external
		override
		onlyOwner
		ensureRewardAsset(_asset)
	{
		stabilityPoolRewards[_asset].rewardDistributionPerMin =
			_weeklyReward /
			DISTRIBUTION_DURATION;

		emit SetNewWeeklyRewardDistribution(_asset, _weeklyReward);
	}

	function getLastUpdateIssuance(address _asset)
		public
		view
		override
		returns (uint256 issuance_, uint256 totalIssuance_)
	{
		DistributionRewards memory distributionRewards = stabilityPoolRewards[_asset];

		if (distributionRewards.lastUpdateTime == 0)
			return (0, distributionRewards.totalRewardIssued);

		uint256 timePassedInMinutes = (block.timestamp -
			distributionRewards.lastUpdateTime) / SECONDS_IN_ONE_MINUTE;
		issuance_ = distributionRewards.rewardDistributionPerMin * timePassedInMinutes;
		totalIssuance_ = issuance_ + distributionRewards.totalRewardIssued;

		if (totalIssuance_ > distributionRewards.totalRewardSupply) {
			issuance_ =
				distributionRewards.totalRewardSupply -
				distributionRewards.totalRewardIssued;
			totalIssuance_ = distributionRewards.totalRewardSupply;
		}

		return (issuance_, totalIssuance_);
	}

	function getRewardsLeftInStabilityPool(address _asset)
		external
		view
		override
		returns (uint256)
	{
		(, uint256 totalIssuance) = getLastUpdateIssuance(_asset);

		return stabilityPoolRewards[_asset].totalRewardSupply - totalIssuance;
	}

	function getRewardDistribution(address _asset)
		external
		view
		override
		returns (DistributionRewards memory)
	{
		return stabilityPoolRewards[_asset];
	}

	function getAllRewardAssets() external view override returns (address[] memory) {
		return rewardAssets;
	}

	function isRewardAsset(address _asset) external view override returns (bool) {
		return isRewardAssetLookup[_asset];
	}
}

