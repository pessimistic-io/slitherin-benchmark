// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "./BaseVesta.sol";
import { TokenTransferrer } from "./TokenTransferrer.sol";
import "./VestaMath.sol";
import "./IStabilityPool.sol";
import "./StabilityPoolModel.sol";
import "./ICommunityIssuance.sol";
import "./IStableCoin.sol";

contract StabilityPool is IStabilityPool, TokenTransferrer, BaseVesta {
	bytes1 public constant LENDING = 0x01;
	uint256 public constant DECIMAL_PRECISION = 1 ether;

	ICommunityIssuance public communityIssuance;
	address public VST;

	mapping(address => uint256) internal deposits; // depositor address -> amount
	mapping(address => Snapshots) internal depositSnapshots; // depositor address -> snapshot
	mapping(uint256 => address) internal assetAddresses;
	mapping(address => uint256) internal assetBalances;
	mapping(address => bool) internal isStabilityPoolAsset;

	uint256 public numberOfAssets;
	uint256 public totalVSTDeposits;

	uint256 public P;

	uint256 public constant SCALE_FACTOR = 1e9;

	uint128 public currentScale;

	uint128 public currentEpoch;

	mapping(address => mapping(uint128 => mapping(uint128 => uint256)))
		internal epochToScaleToSum;

	mapping(address => mapping(uint128 => mapping(uint128 => uint256)))
		internal epochToScaleToG;

	// Error tracker for the error correction in the VSTA issuance calculation
	mapping(address => uint256) internal lastRewardError;
	// Error trackers for the error correction in the offset calculation
	mapping(address => uint256) internal lastAssetError_Offset;
	uint256 public lastVSTLossError_Offset;

	modifier ensureNotPoolAsset(address _asset) {
		if (isStabilityPoolAsset[_asset]) revert IsAlreadyPoolAsset();
		_;
	}

	modifier ensureIsPoolAsset(address _asset) {
		if (!isStabilityPoolAsset[_asset]) revert IsNotPoolAsset();
		_;
	}

	function setUp(
		address _lendingAddress,
		address _communityIssuanceAddress,
		address _vst
	)
		external
		initializer
		onlyContracts(_lendingAddress, _communityIssuanceAddress)
		onlyContract(_vst)
	{
		__BASE_VESTA_INIT();

		communityIssuance = ICommunityIssuance(_communityIssuanceAddress);
		VST = _vst;
		_setPermission(_lendingAddress, LENDING);
		P = DECIMAL_PRECISION;
	}

	function addAsset(address _asset)
		external
		override
		onlyOwner
		ensureNotPoolAsset(_asset)
	{
		isStabilityPoolAsset[_asset] = true;
		assetAddresses[numberOfAssets] = _asset;
		++numberOfAssets;

		emit AssetAddedToStabilityPool(_asset);
	}

	function provideToSP(uint256 _amount)
		external
		override
		nonReentrant
		notZero(_amount)
	{
		_triggerRewardsIssuance();
		_payOutRewardGains();

		_payOutDepositorAssetGains();

		uint256 compoundedVSTDeposit = getCompoundedVSTDeposit(msg.sender);
		_announceVSTLoss(compoundedVSTDeposit);

		_updateDepositAndSnapshots(msg.sender, compoundedVSTDeposit + _amount);

		_sendVSTtoStabilityPool(msg.sender, _amount);
	}

	function withdrawFromSP(uint256 _amount) external override nonReentrant {
		_triggerRewardsIssuance();
		_payOutRewardGains();

		_payOutDepositorAssetGains();

		uint256 compoundedVSTDeposit = getCompoundedVSTDeposit(msg.sender);
		_announceVSTLoss(compoundedVSTDeposit);

		uint256 VSTtoWithdraw = VestaMath.min(_amount, compoundedVSTDeposit);
		_updateDepositAndSnapshots(msg.sender, compoundedVSTDeposit - VSTtoWithdraw);

		_sendVSTToDepositor(msg.sender, VSTtoWithdraw);
	}

	//TODO VFS-91
	function offset(
		address _asset,
		uint256 _debtToOffset,
		uint256 _collToAdd
	) external override hasPermissionOrOwner(LENDING) ensureIsPoolAsset(_asset) {
		uint256 totalVST = totalVSTDeposits;
		if (totalVST == 0 || _debtToOffset == 0) {
			return;
		}

		_triggerRewardsIssuance();

		(
			uint256 AssetGainPerUnitStaked,
			uint256 VSTLossPerUnitStaked
		) = _computeRewardsPerUnitStaked(_asset, _collToAdd, _debtToOffset, totalVST);

		_updateRewardSumAndProduct(_asset, AssetGainPerUnitStaked, VSTLossPerUnitStaked);

		_moveOffsetCollAndDebt(_asset, _collToAdd, _debtToOffset);
	}

	function _computeRewardsPerUnitStaked(
		address _asset,
		uint256 _collToAdd,
		uint256 _debtToOffset,
		uint256 _totalVSTDeposits
	)
		internal
		returns (uint256 assetGainPerUnitStaked_, uint256 vstLossPerUnitStaked_)
	{
		uint256 AssetNumerator = _collToAdd *
			DECIMAL_PRECISION +
			lastAssetError_Offset[_asset];

		assert(_debtToOffset <= _totalVSTDeposits);

		if (_debtToOffset == _totalVSTDeposits) {
			vstLossPerUnitStaked_ = DECIMAL_PRECISION; // When the Pool depletes to 0, so does each deposit
			lastVSTLossError_Offset = 0;
		} else {
			uint256 VSTLossNumerator = _debtToOffset *
				DECIMAL_PRECISION -
				lastVSTLossError_Offset;
			/*
			 * Add 1 to make error in quotient positive. We want "slightly too much" VST loss,
			 * which ensures the error in any given compoundedVSTDeposit favors the Stability Pool.
			 */
			vstLossPerUnitStaked_ = VSTLossNumerator / _totalVSTDeposits + 1;
			lastVSTLossError_Offset =
				vstLossPerUnitStaked_ *
				_totalVSTDeposits -
				VSTLossNumerator;
		}

		assetGainPerUnitStaked_ = AssetNumerator / _totalVSTDeposits;
		lastAssetError_Offset[_asset] =
			AssetNumerator -
			(assetGainPerUnitStaked_ * _totalVSTDeposits);

		return (assetGainPerUnitStaked_, vstLossPerUnitStaked_);
	}

	function _updateRewardSumAndProduct(
		address _asset,
		uint256 _AssetGainPerUnitStaked,
		uint256 _VSTLossPerUnitStaked
	) internal {
		uint256 currentP = P;
		uint256 newP;

		assert(_VSTLossPerUnitStaked <= DECIMAL_PRECISION);

		uint256 newProductFactor = uint256(DECIMAL_PRECISION) - _VSTLossPerUnitStaked;

		uint128 currentScaleCached = currentScale;
		uint128 currentEpochCached = currentEpoch;
		uint256 currentS = epochToScaleToSum[_asset][currentEpochCached][
			currentScaleCached
		];

		uint256 marginalAssetGain = _AssetGainPerUnitStaked * currentP;
		uint256 newS = currentS + marginalAssetGain;
		epochToScaleToSum[_asset][currentEpochCached][currentScaleCached] = newS;
		emit S_Updated(_asset, newS, currentEpochCached, currentScaleCached);

		// If the Stability Pool was emptied, increment the epoch, and reset the scale and product P
		if (newProductFactor == 0) {
			currentEpoch = currentEpochCached + 1;
			emit EpochUpdated(currentEpoch);
			currentScale = 0;
			emit ScaleUpdated(currentScale);
			newP = DECIMAL_PRECISION;

			// If multiplying P by a non-zero product factor would reduce P below the scale boundary, increment the scale
		} else if ((currentP * newProductFactor) / DECIMAL_PRECISION < SCALE_FACTOR) {
			newP = (currentP * newProductFactor * SCALE_FACTOR) / DECIMAL_PRECISION;
			currentScale = currentScaleCached + 1;
			emit ScaleUpdated(currentScale);
		} else {
			newP = (currentP * newProductFactor) / DECIMAL_PRECISION;
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
		// Call lending to cancel the debt
		_decreaseVST(_debtToOffset);

		// add to balance
		assetBalances[_asset] += _collToAdd;

		// burn vst
		IStableCoin(VST).burn(address(this), _debtToOffset);

		// send assets from lending to this address
		if (_asset == address(0)) {
			// send through payable in tests. In production will call function from LENDING instead.
			return;
		} else {
			_performTokenTransferFrom(
				_asset,
				msg.sender,
				address(this),
				_collToAdd,
				false
			);
		}
	}

	function _triggerRewardsIssuance() internal {
		(address[] memory assets, uint256[] memory issuanceAmounts) = communityIssuance
			.issueAssets();
		_updateG(assets, issuanceAmounts);
	}

	function _updateG(
		address[] memory _assetAddresses,
		uint256[] memory _issuanceAmounts
	) internal {
		address[] memory cachedAssetAddresses = _assetAddresses;
		uint256[] memory cachedIssuanceAmounts = _issuanceAmounts;

		uint256 totalVST = totalVSTDeposits;
		/*
		 * When total deposits is 0, G is not updated. In this case, the VSTA issued can not be obtained by later
		 * depositors - it is missed out on, and remains in the balanceof the CommunityIssuance contract.
		 */
		if (totalVST == 0) {
			return;
		}

		uint256 addressLength = cachedAssetAddresses.length;
		for (uint256 i = 0; i < addressLength; ++i) {
			if (cachedIssuanceAmounts[i] > 0) {
				address assetAddress = cachedAssetAddresses[i];
				uint256 perUnitStaked = _computeRewardTokenPerUnitStaked(
					assetAddress,
					cachedIssuanceAmounts[i],
					totalVST
				);

				uint256 newEpochToScaleToG = epochToScaleToG[assetAddress][currentEpoch][
					currentScale
				] += (perUnitStaked * P);

				emit G_Updated(
					assetAddresses[i],
					newEpochToScaleToG,
					currentEpoch,
					currentScale
				);
			}
		}
	}

	function _computeRewardTokenPerUnitStaked(
		address _asset,
		uint256 _issuance,
		uint256 _totalVSTDeposits
	) internal returns (uint256 _vSTAPerUnitStaked) {
		uint256 VSTANumerator = _issuance * DECIMAL_PRECISION + lastRewardError[_asset];

		_vSTAPerUnitStaked = VSTANumerator / _totalVSTDeposits;
		lastRewardError[_asset] =
			VSTANumerator -
			(_vSTAPerUnitStaked * _totalVSTDeposits);

		return _vSTAPerUnitStaked;
	}

	function _payOutRewardGains() internal {
		uint256 initialDeposit = deposits[msg.sender];
		if (initialDeposit == 0) return;

		address[] memory rewardAssets = communityIssuance.getAllRewardAssets();
		uint256 rewardLength = rewardAssets.length;
		for (uint256 i = 0; i < rewardLength; ++i) {
			uint256 depositorGain = _getRewardGainFromSnapshots(
				rewardAssets[i],
				initialDeposit,
				msg.sender
			);
			if (depositorGain > 0) {
				communityIssuance.sendAsset(rewardAssets[i], msg.sender, depositorGain);
				emit RewardsPaidToDepositor(msg.sender, rewardAssets[i], depositorGain);
			}
		}
	}

	function _getRewardGainFromSnapshots(
		address _asset,
		uint256 _initialStake,
		address _depositor
	) internal view returns (uint256 rewardGain_) {
		Snapshots storage snapshots = depositSnapshots[_depositor];
		uint128 epochSnapshot = snapshots.epoch;
		uint128 scaleSnapshot = snapshots.scale;
		uint256 G_Snapshot = snapshots.G[_asset];
		uint256 P_Snapshot = snapshots.P;

		uint256 firstPortion = epochToScaleToG[_asset][epochSnapshot][scaleSnapshot] -
			G_Snapshot;
		uint256 secondPortion = epochToScaleToG[_asset][epochSnapshot][
			scaleSnapshot + 1
		] / SCALE_FACTOR;

		rewardGain_ =
			((_initialStake * (firstPortion + secondPortion)) / P_Snapshot) /
			DECIMAL_PRECISION;

		return rewardGain_;
	}

	function _payOutDepositorAssetGains() internal {
		uint256 numberOfPoolAssets = numberOfAssets;
		for (uint256 i = 0; i < numberOfPoolAssets; ++i) {
			uint256 depositorAssetGain = getDepositorAssetGain(
				assetAddresses[i],
				msg.sender
			);

			if (depositorAssetGain > 0) {
				_sendAssetToDepositor(assetAddresses[i], depositorAssetGain);
			}
		}
	}

	function getDepositorAssetGain(address _asset, address _depositor)
		public
		view
		override
		returns (
			uint256 assetGain_ // Used as regular variable for gas optimisation
		)
	{
		uint256 initialDeposit = deposits[_depositor];
		if (initialDeposit == 0) {
			return 0;
		}

		Snapshots storage snapshots = depositSnapshots[_depositor];
		uint128 epochSnapshot = snapshots.epoch;
		uint128 scaleSnapshot = snapshots.scale;
		uint256 S_Snapshot = snapshots.S[_asset];
		uint256 P_Snapshot = snapshots.P;

		uint256 firstPortion = epochToScaleToSum[_asset][epochSnapshot][scaleSnapshot] -
			S_Snapshot;
		uint256 secondPortion = epochToScaleToSum[_asset][epochSnapshot][
			scaleSnapshot + 1
		] / (SCALE_FACTOR);

		assetGain_ =
			((initialDeposit * (firstPortion + secondPortion)) / P_Snapshot) /
			DECIMAL_PRECISION;

		return _sanitizeValue(_asset, assetGain_);
	}

	function _sendAssetToDepositor(address _asset, uint256 _amount) internal {
		assetBalances[_asset] = assetBalances[_asset] - _amount;

		if (_asset == RESERVED_ETH_ADDRESS) {
			(bool success, ) = msg.sender.call{ value: _amount }("");
			if (!success) revert SendEthFailed();
		} else {
			_performTokenTransfer(_asset, msg.sender, _amount, false);
		}

		emit AssetSent(msg.sender, _asset, _amount);
	}

	function _announceVSTLoss(uint256 _compoundedVSTDeposit) internal {
		uint256 vstLoss = deposits[msg.sender] - _compoundedVSTDeposit;
		if (vstLoss > 0) emit VSTLoss(msg.sender, vstLoss);
	}

	function _increaseVST(uint256 _amount) internal {
		uint256 newTotalVSTDeposits = totalVSTDeposits + _amount;
		totalVSTDeposits = newTotalVSTDeposits;
		emit StabilityPoolVSTBalanceUpdated(newTotalVSTDeposits);
	}

	function _decreaseVST(uint256 _amount) internal {
		uint256 newTotalVSTDeposits = totalVSTDeposits - _amount;
		totalVSTDeposits = newTotalVSTDeposits;
		emit StabilityPoolVSTBalanceUpdated(newTotalVSTDeposits);
	}

	function _sendVSTtoStabilityPool(address _address, uint256 _amount) internal {
		if (_amount == 0) {
			return;
		}

		_increaseVST(_amount);

		_performTokenTransferFrom(VST, _address, address(this), _amount, false);
	}

	function _sendVSTToDepositor(address _depositor, uint256 _amount) internal {
		if (_amount == 0) {
			return;
		}

		_decreaseVST(_amount);

		_performTokenTransfer(VST, _depositor, _amount, false);
	}

	function getCompoundedVSTDeposit(address _depositor)
		public
		view
		override
		returns (uint256)
	{
		uint256 initialDeposit = deposits[_depositor];
		if (initialDeposit == 0) {
			return 0;
		}

		return _getCompoundedStakeFromSnapshots(initialDeposit, _depositor);
	}

	function _getCompoundedStakeFromSnapshots(uint256 initialStake, address depositor)
		internal
		view
		returns (uint256)
	{
		Snapshots storage snapshots = depositSnapshots[depositor];
		uint256 snapshot_P = snapshots.P;
		uint128 scaleSnapshot = snapshots.scale;
		uint128 epochSnapshot = snapshots.epoch;

		// If stake was made before a pool-emptying event, then it has been fully cancelled with debt -- so, return 0
		if (epochSnapshot < currentEpoch) {
			return 0;
		}

		uint256 compoundedStake;
		uint128 scaleDiff = currentScale - scaleSnapshot;

		/* Compute the compounded stake. If a scale change in P was made during the stake's lifetime,
		 * account for it. If more than one scale change was made, then the stake has decreased by a factor of
		 * at least 1e-9 -- so return 0.
		 */
		if (scaleDiff == 0) {
			compoundedStake = (initialStake * P) / snapshot_P;
		} else if (scaleDiff == 1) {
			compoundedStake = (initialStake * P) / snapshot_P / SCALE_FACTOR;
		} else {
			compoundedStake = 0;
		}

		/*
		 * If compounded deposit is less than a billionth of the initial deposit, return 0.
		 *
		 * NOTE: originally, this line was in place to stop rounding errors making the deposit too large. However, the error
		 * corrections should ensure the error in P "favors the Pool", i.e. any given compounded deposit should slightly less
		 * than it's theoretical value.
		 *
		 * Thus it's unclear whether this line is still really needed.
		 */
		if (compoundedStake < initialStake / 1e9) {
			return 0;
		}

		return compoundedStake;
	}

	function _updateDepositAndSnapshots(address _depositor, uint256 _newValue)
		internal
	{
		deposits[_depositor] = _newValue;

		if (_newValue == 0) {
			delete depositSnapshots[_depositor];
			emit UserDepositChanged(_depositor, 0);
			return;
		}

		uint128 currentScaleCached = currentScale;
		uint128 currentEpochCached = currentEpoch;
		uint256 currentP = P;

		Snapshots storage depositSnap = depositSnapshots[_depositor];
		depositSnap.P = currentP;
		depositSnap.scale = currentScaleCached;
		depositSnap.epoch = currentEpochCached;

		address[] memory rewardAssets = communityIssuance.getAllRewardAssets();
		uint256 rewardAssetsLength = rewardAssets.length;
		for (uint256 i = 0; i < rewardAssetsLength; ++i) {
			depositSnap.G[rewardAssets[i]] = epochToScaleToG[rewardAssets[i]][
				currentEpochCached
			][currentScaleCached];
		}

		uint256 numberOfPoolAssets = numberOfAssets;
		for (uint256 i = 0; i < numberOfPoolAssets; ++i) {
			address currentAsset = assetAddresses[i];
			depositSnap.S[currentAsset] = epochToScaleToSum[currentAsset][
				currentEpochCached
			][currentScaleCached];
		}

		emit UserDepositChanged(_depositor, _newValue);
	}

	function isStabilityPoolAssetLookup(address _asset)
		external
		view
		override
		returns (bool)
	{
		return isStabilityPoolAsset[_asset];
	}

	function getPoolAssets() external view returns (address[] memory poolAssets_) {
		uint256 poolAssetLength = numberOfAssets;
		poolAssets_ = new address[](poolAssetLength);
		for (uint256 i = 0; i < poolAssetLength; ++i) {
			poolAssets_[i] = assetAddresses[i];
		}
	}

	function getUserG(address _user, address _asset) external view returns (uint256) {
		return depositSnapshots[_user].G[_asset];
	}

	function getUserS(address _user, address _asset) external view returns (uint256) {
		return depositSnapshots[_user].S[_asset];
	}

	function getUserP(address _user) external view returns (uint256) {
		return depositSnapshots[_user].P;
	}

	function getUserEpoch(address _user) external view returns (uint256) {
		return depositSnapshots[_user].epoch;
	}

	function getUserScale(address _user) external view returns (uint256) {
		return depositSnapshots[_user].scale;
	}

	// add to interface
	function snapshotG(
		address _asset,
		uint128 _epoch,
		uint128 _scale
	) external view returns (uint256) {
		return epochToScaleToG[_asset][_epoch][_scale];
	}

	function snapshotS(
		address _asset,
		uint128 _epoch,
		uint128 _scale
	) external view returns (uint256) {
		return epochToScaleToSum[_asset][_epoch][_scale];
	}
}


