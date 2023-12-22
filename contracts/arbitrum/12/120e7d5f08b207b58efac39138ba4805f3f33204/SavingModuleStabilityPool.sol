// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import { ISavingModuleStabilityPool } from "./ISavingModuleStabilityPool.sol";
import { ITroveManager } from "./ITroveManager.sol";
import { ISortedTroves } from "./ISortedTroves.sol";
import { IVSTToken } from "./IVSTToken.sol";
import { IVestaParameters, IActivePool, IPriceFeed } from "./IVestaParameters.sol";
import { IERC20 } from "./IERC20.sol";
import "./SavingModuleStabilityPoolModel.sol";

import { FullMath } from "./FullMath.sol";

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract SavingModuleStabilityPool is
	ISavingModuleStabilityPool,
	OwnableUpgradeable
{
	uint256 private constant DECIMAL_PRECISION = 1e18;

	address public borrowerOperations;
	ITroveManager public troveManager;
	ISortedTroves public sortedTroves;
	IVSTToken public vstToken;
	IVestaParameters public vestaParams;

	address public savingModule;

	mapping(address => uint256) internal assetBalances;
	mapping(address => bool) private registeredAssets;

	uint256 internal totalVSTDeposits;

	mapping(uint256 => uint256) public deposits; // depositor lockId -> amount
	mapping(uint256 => Snapshots) public depositSnapshots; // lockId -> snapshots struct

	uint256 public totalStakes;
	Snapshots public systemSnapshots;

	/*  Product 'P': Running product by which to multiply an initial deposit, in order to find the current compounded deposit,
	 * after a series of liquidations have occurred, each of which cancel some VST debt with the deposit.
	 *
	 * During its lifetime, a deposit's value evolves from d_t to d_t * P / P_t , where P_t
	 * is the snapshot of P taken at the instant the deposit was made. 18-digit decimal.
	 */
	uint256 public P;

	uint256 public constant SCALE_FACTOR = 1e9;

	// Each time the scale of P shifts by SCALE_FACTOR, the scale is incremented by 1
	uint128 public currentScale;

	// With each offset that fully empties the Pool, the epoch is incremented by 1
	uint128 public currentEpoch;

	/* ETH Gain sum 'S': During its lifetime, each deposit d_t earns an ETH gain of ( d_t * [S - S_t] )/P_t, where S_t
	 * is the depositor's snapshot of S taken at the time t when the deposit was made.
	 *
	 * The 'S' sums are stored in a nested mapping (asset => epoch => scale => sum):
	 *
	 * - The inner mapping records the sum S at different scales
	 * - The outer mapping records the (scale => sum) mappings, for different epochs.
	 */
	mapping(address => mapping(uint128 => mapping(uint128 => uint256)))
		private epochToScaleToSum;

	mapping(address => uint256) private lastAssetError_Offset;
	mapping(address => uint256) private lastVSTLossError_Offset;

	address[] private assets;

	modifier onlyActivePool() {
		if (msg.sender != address(vestaParams.activePool()))
			revert NotActivePool();
		_;
	}

	modifier onlyTroveManager() {
		if (msg.sender != address(troveManager)) revert NotTroveManager();
		_;
	}

	modifier onlySavingModule() {
		if (msg.sender != savingModule) revert NotSavingModule();
		_;
	}

	modifier nonZeroValue(uint256 _value) {
		_requireHigherThanZero(_value);
		_;
	}

	function _requireHigherThanZero(uint256 _number) private pure {
		if (_number == 0) revert ValueCannotBeZero();
	}

	function _requireNoUnderCollateralizedTroves() private view {
		uint256 length = assets.length;

		uint256 price;
		address lowestTrove;
		uint256 ICR;
		address asset;

		for (uint256 i = 0; i < length; ++i) {
			asset = assets[i];
			price = vestaParams.priceFeed().getExternalPrice(asset);
			lowestTrove = sortedTroves.getLast(asset);
			ICR = troveManager.getCurrentICR(asset, lowestTrove, price);

			if (ICR < vestaParams.MCR(asset)) revert VaultsPendingLiquidation();
		}
	}

	function setUp(
		address _borrowerOperationsAddress,
		address _troveManagerAddress,
		address _vstTokenAddress,
		address _sortedTrovesAddress,
		address _savingModule,
		address _vestaParamsAddress
	) external initializer {
		__Ownable_init();

		borrowerOperations = _borrowerOperationsAddress;
		troveManager = ITroveManager(_troveManagerAddress);
		vstToken = IVSTToken(_vstTokenAddress);
		sortedTroves = ISortedTroves(_sortedTrovesAddress);
		vestaParams = IVestaParameters(_vestaParamsAddress);
		savingModule = _savingModule;

		P = DECIMAL_PRECISION;
		assets.push(address(0));
		registeredAssets[address(0)] = true;
	}

	function provideToSP(
		address _lockOwner,
		uint256 _lockId,
		uint256 _amount
	) external override onlySavingModule nonZeroValue(_amount) {
		uint256 initialDeposit = deposits[_lockId];

		if (initialDeposit != 0) revert LockAlreadyExists();

		uint256 compoundedStake = getCompoundedTotalStake();
		uint256 newStake = compoundedStake + _amount;
		_updateStakeAndSnapshots(newStake);
		emit StakeChanged(newStake);

		_sendVSTtoStabilityPool(_lockOwner, _amount);
		_updateDepositAndSnapshots(_lockId, _amount);

		emit LockDepositChanged(_lockId, _amount);
	}

	function withdrawFromSP(
		address _lockOwner,
		uint256 _lockId,
		uint256 _amount
	) external override onlySavingModule {
		if (_amount != 0) {
			_requireNoUnderCollateralizedTroves();
		}

		uint256 initialDeposit = deposits[_lockId];
		_requireHigherThanZero(initialDeposit);

		(, uint256[] memory lockAssetGains) = _getLockAssetsGain(
			initialDeposit,
			_lockId
		);

		uint256 compoundedVSTDeposit = _getCompoundedVSTDeposit(
			_lockId,
			initialDeposit
		);

		uint256 vstToWitdraw = _amount < compoundedVSTDeposit
			? _amount
			: compoundedVSTDeposit;

		uint256 vstLoss = initialDeposit - compoundedVSTDeposit;

		uint256 compoundedStake = getCompoundedTotalStake();
		uint256 newStake = compoundedStake - vstToWitdraw;

		_updateStakeAndSnapshots(newStake);
		emit StakeChanged(newStake);

		_sendVSTToDepositor(_lockOwner, vstToWitdraw);

		uint256 newDeposit = compoundedVSTDeposit - vstToWitdraw;
		_updateDepositAndSnapshots(_lockId, newDeposit);

		emit LockDepositChanged(_lockId, newDeposit);
		emit VSTLoss(_lockId, vstLoss);

		_sendAssetGainToDepositor(_lockOwner, lockAssetGains);
	}

	function offset(
		address _asset,
		uint256 _debtToOffset,
		uint256 _collToAdd
	) external override onlyTroveManager {
		uint256 totalVST = totalVSTDeposits;
		if (totalVST == 0 || _debtToOffset == 0) {
			return;
		}

		(
			uint256 assetGainPerUnit,
			uint256 vstLossPerUnit
		) = _computeRewardsPerUnitStaked(
				_asset,
				_collToAdd,
				_debtToOffset,
				totalVST
			);

		_updateRewardSumAndProduct(_asset, assetGainPerUnit, vstLossPerUnit);

		_moveOffsetCollAndDebt(_asset, _collToAdd, _debtToOffset);
	}

	function _computeRewardsPerUnitStaked(
		address _asset,
		uint256 _collToAdd,
		uint256 _debtToOffset,
		uint256 _totalVSTDeposits
	)
		internal
		returns (uint256 assetGainPerUnitStaked, uint256 vstLossPerUnitStaked)
	{
		uint256 assetNumerator = (_collToAdd * DECIMAL_PRECISION) +
			lastAssetError_Offset[_asset];

		assert(_debtToOffset <= _totalVSTDeposits);

		if (_debtToOffset == _totalVSTDeposits) {
			vstLossPerUnitStaked = DECIMAL_PRECISION;
			lastVSTLossError_Offset[_asset] = 0;
		} else {
			uint256 vstLossNumerator = (_debtToOffset * DECIMAL_PRECISION) -
				lastVSTLossError_Offset[_asset];

			vstLossPerUnitStaked = (vstLossNumerator / _totalVSTDeposits) + 1;

			lastVSTLossError_Offset[_asset] =
				(vstLossPerUnitStaked * _totalVSTDeposits) -
				vstLossNumerator;
		}

		assetGainPerUnitStaked = assetNumerator / _totalVSTDeposits;
		lastAssetError_Offset[_asset] =
			(assetNumerator - assetGainPerUnitStaked) *
			_totalVSTDeposits;

		return (assetGainPerUnitStaked, vstLossPerUnitStaked);
	}

	function _updateRewardSumAndProduct(
		address _asset,
		uint256 _assetGainPerUnitStaked,
		uint256 _vstLossPerUnitStaked
	) internal {
		uint256 currentP = P;
		uint256 newP;

		assert(_vstLossPerUnitStaked <= DECIMAL_PRECISION);

		uint256 newProductFactor = uint256(DECIMAL_PRECISION) -
			_vstLossPerUnitStaked;

		uint128 currentScaleCached = currentScale;
		uint128 currentEpochCached = currentEpoch;
		uint256 currentS = epochToScaleToSum[_asset][currentEpochCached][
			currentScaleCached
		];

		uint256 marginalAssetGain = _assetGainPerUnitStaked * currentP;
		uint256 newS = currentS + marginalAssetGain;

		epochToScaleToSum[_asset][currentEpochCached][
			currentScaleCached
		] = newS;

		emit S_Updated(_asset, newS, currentEpochCached, currentScaleCached);

		if (newProductFactor == 0) {
			currentEpoch = currentEpochCached + 1;
			emit EpochUpdated(currentEpoch);

			currentScale = 0;
			emit ScaleUpdated(currentScale);

			newP = DECIMAL_PRECISION;
		} else if (
			FullMath.mulDiv(currentP, newProductFactor, DECIMAL_PRECISION) <
			SCALE_FACTOR
		) {
			newP = FullMath.mulDiv(
				currentP * newProductFactor,
				SCALE_FACTOR,
				DECIMAL_PRECISION
			);

			currentScale = currentScaleCached + 1;
			emit ScaleUpdated(currentScale);
		} else {
			newP = FullMath.mulDiv(
				currentP,
				newProductFactor,
				DECIMAL_PRECISION
			);
		}

		assert(newP > 0);
		P = newP;

		emit P_Updated(newP);
	}

	function _moveOffsetCollAndDebt(
		address _asset,
		uint256 _collToAdd,
		uint256 _debtToOffset
	) internal {
		IActivePool activePoolCached = vestaParams.activePool();

		activePoolCached.decreaseVSTDebt(_asset, _debtToOffset);
		_decreaseVST(_debtToOffset);

		vstToken.burn(address(this), _debtToOffset);

		activePoolCached.sendAsset(_asset, address(this), _collToAdd);

		if (!registeredAssets[_asset]) {
			registeredAssets[_asset] = true;
			assets.push(_asset);
		}
	}

	function _decreaseVST(uint256 _amount) internal {
		totalVSTDeposits -= _amount;
		emit VSTBalanceUpdated(totalVSTDeposits);
	}

	function getLockAssetsGain(uint256 _lockId)
		public
		view
		override
		returns (address[] memory, uint256[] memory)
	{
		return _getLockAssetsGain(deposits[_lockId], _lockId);
	}

	function _getLockAssetsGain(uint256 _initialDeposit, uint256 _lockId)
		private
		view
		returns (address[] memory, uint256[] memory)
	{
		if (_initialDeposit == 0) {
			return (assets, new uint256[](assets.length));
		}

		return (assets, _getLockGainsFromSnapshot(_initialDeposit, _lockId));
	}

	function _getLockGainsFromSnapshot(
		uint256 _initialDeposit,
		uint256 _lockId
	) internal view returns (uint256[] memory assetGains) {
		Snapshots storage snapshots = depositSnapshots[_lockId];

		uint128 epochSnapshot = snapshots.epoch;
		uint128 scaleSnapshot = snapshots.scale;
		uint256 S_Snapshot;
		uint256 P_Snapshot = snapshots.P;

		uint256 totalAssets = assets.length;
		assetGains = new uint256[](totalAssets);

		uint256 firstPortion;
		uint256 secondPortion;
		address asset;

		for (uint256 i = 0; i < totalAssets; ++i) {
			asset = assets[i];
			S_Snapshot = snapshots.S[asset];

			firstPortion =
				epochToScaleToSum[asset][epochSnapshot][scaleSnapshot] -
				S_Snapshot;

			secondPortion =
				epochToScaleToSum[asset][epochSnapshot][scaleSnapshot + 1] /
				SCALE_FACTOR;

			//prettier-ignore
			assetGains[i] =
				FullMath.mulDiv(
					_initialDeposit,
					firstPortion + secondPortion,
					P_Snapshot
				) / DECIMAL_PRECISION;
		}

		return assetGains;
	}

	function getCompoundedVSTDeposit(uint256 _lockId)
		public
		view
		override
		returns (uint256)
	{
		return _getCompoundedVSTDeposit(_lockId, deposits[_lockId]);
	}

	function _getCompoundedVSTDeposit(
		uint256 _lockId,
		uint256 _initialDeposit
	) private view returns (uint256) {
		if (_initialDeposit == 0) return 0;

		return
			_getCompoundedStakeFromSnapshots(
				_initialDeposit,
				depositSnapshots[_lockId]
			);
	}

	function getCompoundedTotalStake()
		public
		view
		override
		returns (uint256)
	{
		uint256 cachedStake = totalStakes;
		if (cachedStake == 0) {
			return 0;
		}

		return _getCompoundedStakeFromSnapshots(cachedStake, systemSnapshots);
	}

	function _getCompoundedStakeFromSnapshots(
		uint256 initialStake,
		Snapshots storage snapshots
	) internal view returns (uint256) {
		uint256 snapshot_P = snapshots.P;
		uint128 scaleSnapshot = snapshots.scale;
		uint128 epochSnapshot = snapshots.epoch;

		if (epochSnapshot < currentEpoch) return 0;

		uint256 compoundedStake;
		uint128 scaleDiff = currentScale - scaleSnapshot;

		if (scaleDiff == 0) {
			compoundedStake = FullMath.mulDiv(initialStake, P, snapshot_P);
		} else if (scaleDiff == 1) {
			compoundedStake =
				FullMath.mulDiv(initialStake, P, snapshot_P) /
				SCALE_FACTOR;
		}

		if (compoundedStake < initialStake / 1e9) return 0;

		return compoundedStake;
	}

	function _sendVSTtoStabilityPool(address _address, uint256 _amount)
		internal
	{
		vstToken.sendToPool(_address, address(this), _amount);
		totalVSTDeposits += _amount;
		emit VSTBalanceUpdated(totalVSTDeposits);
	}

	function _sendAssetGainToDepositor(
		address _receiver,
		uint256[] memory _amounts
	) internal {
		uint256[] memory cachedAmounts = _amounts;
		uint256 size = cachedAmounts.length;

		uint256 amount;
		address asset;
		for (uint256 i = 0; i < size; ++i) {
			amount = cachedAmounts[i];
			if (amount == 0) continue;

			asset = assets[i];
			uint256 logBalance = assetBalances[asset] -= amount;

			if (asset == address(0)) {
				(bool success, ) = _receiver.call{ value: amount }("");
				require(success, "StabilityPool: sending ETH failed");
			} else {
				IERC20(asset).transfer(_receiver, _sanitizeValue(asset, amount));
			}

			emit AssetSent(_receiver, amount);
			emit AssetBalanceUpdated(asset, logBalance);
		}
	}

	function _sanitizeValue(address token, uint256 value)
		internal
		view
		returns (uint256)
	{
		if (token == address(0) || value == 0) return value;

		uint8 decimals = IERC20(token).decimals();

		if (decimals < 18) {
			return value / (10**(18 - decimals));
		}

		return value;
	}

	function _sendVSTToDepositor(address _depositor, uint256 VSTWithdrawal)
		internal
	{
		if (VSTWithdrawal == 0) return;

		vstToken.returnFromPool(address(this), _depositor, VSTWithdrawal);
		_decreaseVST(VSTWithdrawal);
	}

	function _updateDepositAndSnapshots(uint256 _lockId, uint256 _newValue)
		internal
	{
		deposits[_lockId] = _newValue;

		if (_newValue == 0) {
			delete depositSnapshots[_lockId];
			emit LockSnapshotUpdated(_lockId, 0, 0);

			return;
		}

		Snapshots storage depositSnap = depositSnapshots[_lockId];

		uint256 totalAsset = assets.length;
		uint256 currentS;
		address asset;

		depositSnap.P = P;
		depositSnap.scale = currentScale;
		depositSnap.epoch = currentEpoch;

		for (uint256 i = 0; i < totalAsset; ++i) {
			asset = assets[i];
			currentS = epochToScaleToSum[asset][currentEpoch][currentScale];
			depositSnap.S[asset] = currentS;
		}

		emit LockSnapshotUpdated(_lockId, P, currentS);
	}

	function _updateStakeAndSnapshots(uint256 _newValue) internal {
		Snapshots storage snapshots = systemSnapshots;
		totalStakes = _newValue;

		uint128 currentScaleCached = currentScale;
		uint128 currentEpochCached = currentEpoch;
		uint256 currentP = P;

		snapshots.P = currentP;
		snapshots.scale = currentScaleCached;
		snapshots.epoch = currentEpochCached;

		emit SystemSnapshotUpdated(currentP);
	}

	function getAssets() external view override returns (address[] memory) {
		return assets;
	}

	function getAssetBalances()
		external
		view
		override
		returns (uint256[] memory balances_)
	{
		uint256 length = assets.length;
		balances_ = new uint256[](length);

		for (uint256 i = 0; i < length; ++i) {
			balances_[i] = assetBalances[assets[i]];
		}

		return balances_;
	}

	function getTotalVSTDeposits() external view override returns (uint256) {
		return totalVSTDeposits;
	}

	function receivedERC20(address _asset, uint256 _amount)
		external
		override
		onlyActivePool
	{
		uint256 logValue = assetBalances[_asset] += _amount;

		emit AssetBalanceUpdated(_asset, logValue);
	}

	receive() external payable onlyActivePool {
		uint256 logValue = assetBalances[address(0)] += msg.value;
		emit AssetBalanceUpdated(address(0), logValue);
	}
}


