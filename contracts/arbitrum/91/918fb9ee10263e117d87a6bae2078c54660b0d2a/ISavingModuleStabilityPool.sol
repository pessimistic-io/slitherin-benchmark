// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface ISavingModuleStabilityPool {
	error NotActivePool();
	error NotTroveManager();
	error ValueCannotBeZero();
	error NotSavingModule();
	error VaultsPendingLiquidation();
	error LockAlreadyExists();

	event StakeChanged(uint256 stake);
	event LockDepositChanged(uint256 indexed lockId, uint256 deposit);
	event VSTLoss(uint256 indexed lockId, uint256 vstLost);
	event S_Updated(
		address indexed asset,
		uint256 newS,
		uint256 epoch,
		uint256 scale
	);
	event EpochUpdated(uint256 epoch);
	event ScaleUpdated(uint256 scale);
	event P_Updated(uint256 newP);
	event VSTBalanceUpdated(uint256 balance);
	event AssetSent(address indexed user, uint256 amount);
	event AssetBalanceUpdated(address indexed asset, uint256 amount);
	event LockSnapshotUpdated(
		uint256 indexed lockId,
		uint256 p,
		uint256 scale
	);
	event SystemSnapshotUpdated(uint256 P);

	function provideToSP(
		address _receiver,
		uint256 _lockId,
		uint256 _amount
	) external;

	function withdrawFromSP(
		address _receiver,
		uint256 _lockId,
		uint256 _amount
	) external;

	function offset(
		address _asset,
		uint256 _debtToOffset,
		uint256 _collToAdd
	) external;

	function getLockAssetsGain(uint256 _lockId)
		external
		view
		returns (address[] memory, uint256[] memory);

	function getCompoundedVSTDeposit(uint256 _lockId)
		external
		view
		returns (uint256);

	function getCompoundedTotalStake() external view returns (uint256);

	function getAssets() external view returns (address[] memory);

	function getAssetBalances() external view returns (uint256[] memory);

	function getTotalVSTDeposits() external view returns (uint256);

	function receivedERC20(address _asset, uint256 _amount) external;
}


