// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./SafeERC20.sol";

interface IPSYStaking {
	// --- Events --

	event TreasuryAddressChanged(address _treausury);
	event SentToTreasury(address indexed _asset, uint256 _amount);
	event PSYTokenAddressSet(address _PSYTokenAddress);
	event SLSDTokenAddressSet(address _slsdTokenAddress);
	event TroveManagerAddressSet(address _troveManager);
	event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
	event ActivePoolAddressSet(address _activePoolAddress);

	event StakeChanged(address indexed staker, uint256 newStake);
	event StakingGainsAssetWithdrawn(
		address indexed staker,
		address indexed asset,
		uint256 AssetGain
	);
	event StakingGainsSLSDWithdrawn(address indexed staker, uint256 SLSDGain);
	event F_AssetUpdated(address indexed _asset, uint256 _F_ASSET);
	event F_SLSDUpdated(uint256 _F_SLSD);
	event TotalPSYStakedUpdated(uint256 _totalPSYStaked);
	event AssetSent(address indexed _asset, address indexed _account, uint256 _amount);
	event StakerSnapshotsUpdated(address _staker, uint256 _F_Asset, uint256 _F_SLSD);

	function psyToken() external view returns (IERC20);

	// --- Functions ---

	function setAddresses(
		address _PSYTokenAddress,
		address _slsdTokenAddress,
		address _troveManagerAddress,
		address _troveManagerHelpersAddress,
		address _borrowerOperationsAddress,
		address _activePoolAddress,
		address _treasury
	) external;

	function stake(uint256 _PSYamount) external;

	function unstake(uint256 _PSYamount) external;

	function increaseF_Asset(address _asset, uint256 _AssetFee) external;

	function increaseF_SLSD(uint256 _PSYFee) external;

	function getPendingAssetGain(address _asset, address _user) external view returns (uint256);

	function getPendingSLSDGain(address _user) external view returns (uint256);
}

