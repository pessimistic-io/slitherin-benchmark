// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./CommunityIssuanceModel.sol";

interface ICommunityIssuance {
	error IsNotRewardAsset();
	error IsAlreadyRewardAsset();
	error RewardSupplyCannotBeBelowIssued();
	error BalanceMustBeZero();
	error RewardsStillActive();

	event StabilityPoolAddressSet(address _stabilityPoolAddress);
	event AssetIssuanceUpdated(
		address indexed _asset,
		uint256 _issuanceSinceLastUpdate,
		uint256 _totalIssued,
		uint256 lastUpdateTime
	);
	event SetNewWeeklyRewardDistribution(
		address indexed _asset,
		uint256 _weeklyReward
	);
	event AddRewardAsset(address _asset);
	event DisableRewardAsset(address _asset);
	event RemoveRewardAsset(address _asset);
	event AddFundsToStabilityPool(address _asset, uint256 _amount);
	event RemoveFundsToStabilityPool(address _asset, uint256 _amount);

	/** 
	@notice addRewardAsset add an asset to array of supported reward assets to distribute.
	@param _asset asset address
	@param _weeklyReward weekly reward amount
	 */
	function addRewardAsset(address _asset, uint256 _weeklyReward) external;

	/** 
	@notice disableRewardAsset stops an reward asset from issueing more rewards.
	@dev If there are still a bit of unissued assets might want to call issueassets before disabling so last little bit is issued.
	@param _asset asset address
	 */
	function disableRewardAsset(address _asset) external;

	/** 
	@notice removeRewardAsset remove an asset from the array of supported reward assets to distribute.
	@dev Can only remove reward asset if balance of asset in this address is 0. Meaning no more rewards left to claim.
	@param _asset asset address
	 */
	function removeRewardAsset(address _asset) external;

	/** 
	@notice addFundsToStabilityPool add funds to stability pool.
	@dev Can only add assets that are reward assets.
	@param _asset asset address
	@param _amount amount of tokens
	 */
	function addFundsToStabilityPool(address _asset, uint256 _amount) external;

	/** 
	@notice removeFundsFromStabilityPool remove funds from stabilitypool.
	@dev Cannot remove funds such that totalRewardIssued > totalRewardSupply
	@param _asset asset address
	@param _amount amount of tokens
	 */
	function removeFundsFromStabilityPool(address _asset, uint256 _amount) external;

	/** 
	@notice issueAssets go through all reward assets and update the amount issued based on set reward rate and last update time.
	@dev Used to return total amount of reward tokens issued to StabilityPool.
	@return assetAddresses_ array of addresses of assets that got updated
	@return issuanceAmounts_ amount of tokens issued since last update
	 */
	function issueAssets()
		external
		returns (address[] memory assetAddresses_, uint256[] memory issuanceAmounts_);

	/** 
	@notice sendAsset send assets to a user.
	@dev Can only be called by StabilityPool. Relies on StabilityPool to calculate how much tokens each user is entitled to.
	@param _asset asset address
	@param _account address of user
	@param _amount amount of tokens
	 */
	function sendAsset(
		address _asset,
		address _account,
		uint256 _amount
	) external;

	/** 
	@notice setWeeklyAssetDistribution sets how much reward tokens distributed per week.
	@param _asset asset address
	@param _weeklyReward amount of tokens per week
	 */
	function setWeeklyAssetDistribution(address _asset, uint256 _weeklyReward)
		external;

	/** 
	@notice getLastUpdateIssuance returns amount of rewards issued from last update till now.
	@param _asset asset address
	 */
	function getLastUpdateIssuance(address _asset)
		external
		view
		returns (uint256, uint256);

	/** 
	@notice getRewardsLeftInStabilityPool returns total amount of tokens that have not been issued to users. 
	@dev This is calculated using current timestamp assuming issueAssets is called right now.
	@param _asset asset address
	 */
	function getRewardsLeftInStabilityPool(address _asset)
		external
		view
		returns (uint256);

	/** 
	@notice getRewardDistribution returns the reward distribution details of a reward asset.
	@param _asset asset address
	 */
	function getRewardDistribution(address _asset)
		external
		view
		returns (DistributionRewards memory);

	/** 
	@notice getAllRewardAssets returns an array of all reward asset addresses.
	 */
	function getAllRewardAssets() external view returns (address[] memory);

	/** 
	@notice isRewardAsset returns whether address is a reward asset or not.
	@param _asset asset address
	 */
	function isRewardAsset(address _asset) external view returns (bool);
}


