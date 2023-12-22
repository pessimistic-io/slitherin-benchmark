// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

interface IStabilityPool {
	// --- Errors ---
	error IsAlreadyPoolAsset();
	error IsNotPoolAsset();
	error SendEthFailed();

	// --- Events ---
	event AssetAddedToStabilityPool(address _asset);
	event RewardsPaidToDepositor(
		address indexed _depositor,
		address _asset,
		uint256 _amount
	);
	event AssetSent(address _to, address _asset, uint256 _amount);
	event VSTLoss(address _depositor, uint256 _vstLoss);
	event UserDepositChanged(address indexed _depositor, uint256 _newDeposit);
	event StabilityPoolVSTBalanceUpdated(uint256 _newBalance);
	event P_Updated(uint256 _P);
	event S_Updated(address _asset, uint256 _S, uint128 _epoch, uint128 _scale);
	event G_Updated(address _asset, uint256 _G, uint128 _epoch, uint128 _scale);
	event EpochUpdated(uint128 _currentEpoch);
	event ScaleUpdated(uint128 _currentScale);

	function addAsset(address _asset) external;

	function provideToSP(uint256 _amount) external;

	function withdrawFromSP(uint256 _amount) external;

	function offset(
		address _asset,
		uint256 _debt,
		uint256 _coll
	) external;

	function getDepositorAssetGain(address _asset, address _depositor)
		external
		view
		returns (uint256);

	function getCompoundedVSTDeposit(address _depositor)
		external
		view
		returns (uint256);

	function isStabilityPoolAssetLookup(address _asset) external view returns (bool);
}


