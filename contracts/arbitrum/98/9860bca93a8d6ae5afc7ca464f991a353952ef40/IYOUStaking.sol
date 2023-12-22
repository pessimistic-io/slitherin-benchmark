// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./SafeERC20Upgradeable.sol";

interface IYOUStaking {
	// --- Events --

	event TreasuryAddressChanged(address _treausury);
	event SentToTreasury(address indexed _asset, uint256 _amount);
	event YOUTokenAddressSet(address _YOUTokenAddress);
	event UTokenAddressSet(address _uTokenAddress);
	event TroveManagerAddressSet(address _troveManager);
	event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
	event ActivePoolAddressSet(address _activePoolAddress);

	event StakeChanged(address indexed staker, uint256 newStake);
	event StakingGainsAssetWithdrawn(
		address indexed staker,
		address indexed asset,
		uint256 AssetGain
	);
	event StakingGainsUWithdrawn(address indexed staker, uint256 UGain);
	event F_AssetUpdated(address indexed _asset, uint256 _F_ASSET);
	event F_UUpdated(uint256 _F_U);
	event TotalYOUStakedUpdated(uint256 _totalYOUStaked);
	event AssetSent(address indexed _asset, address indexed _account, uint256 _amount);
	event StakerSnapshotsUpdated(address _staker, uint256 _F_Asset, uint256 _F_U);

	function youToken() external view returns (IERC20Upgradeable);

	// --- Functions ---

	function setAddresses(
		address _YOUTokenAddress,
		address _uTokenAddress,
		address _troveManagerAddress,
		address _borrowerOperationsAddress,
		address _activePoolAddress,
		address _treasury
	) external;

	function stake(uint256 _YOUamount) external;

	function unstake(uint256 _YOUamount) external;

	function increaseF_Asset(address _asset, uint256 _AssetFee) external;

	function increaseF_U(uint256 _YOUFee) external;

	function getPendingAssetGain(address _asset, address _user) external view returns (uint256);

	function getPendingUGain(address _user) external view returns (uint256);
}

