// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC20 } from "./IERC20.sol";
import { FullMath } from "./FullMath.sol";
import { ISavingModule } from "./ISavingModule.sol";
import { ISavingModuleStabilityPool } from "./ISavingModuleStabilityPool.sol";

import { Lock } from "./SavingModuleModel.sol";

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { EnumerableSetUpgradeable as Set } from "./EnumerableSetUpgradeable.sol";

import { UD60x18, ud, intoUint256 } from "./UD60x18.sol";

import { Shareable } from "./Shareable.sol";
import { IInterestManager } from "./IInterestManager.sol";

contract SavingModule is ISavingModule, OwnableUpgradeable, Shareable {
	using Set for Set.UintSet;

	uint256 public constant YEAR_MINUTE = 1.901285e12;
	uint256 public constant COMPOUND = 2.71828e18;
	uint16 public constant BPS = 10_000;

	ISavingModuleStabilityPool public stabilityPool;

	address public vst;
	address public vrrManager;
	uint256 public maxVST;
	uint256 public maxLockDays;

	uint256 public vrrGeneratedRevenueTracker;
	uint256 public rewardAllocation;
	uint256 public interestMinted_DEPRECATED; // unused

	uint16 public allocationBPS;
	uint16 public interestCapBPS;

	uint256 public lastUpdate;
	uint256 public releaseDate; // Unused

	Lock[] internal locks;
	mapping(address => Set.UintSet) private userLocks;

	address public emergencyReserve;
	uint256 public lastVRRAmountReceived;
	uint256 public lastVRRRatePerSecond;

	modifier onlyVRROrOwner() {
		if (msg.sender != vrrManager && msg.sender != owner()) {
			revert NoPermission();
		}

		_;
	}

	modifier lockExists(uint256 _id, address _user) {
		if (locks.length >= _id || locks[_id].user != _user) {
			revert LockNotFoundOrExpired();
		}

		_;
	}

	function setUp(
		address _vst,
		address _vrrManager,
		address _stabilityPool,
		uint16 _allocationBPS,
		uint16 _interestCapBPS
	) external initializer {
		__Ownable_init();
		vrrManager = _vrrManager;
		allocationBPS = _allocationBPS;
		interestCapBPS = _interestCapBPS;
		vst = _vst;
		maxLockDays = 90;

		stabilityPool = ISavingModuleStabilityPool(_stabilityPool);
		lastUpdate = block.timestamp;
		maxVST = 1_000_000e18;
		releaseDate = block.timestamp;
	}

	function depositVST(uint256 _amount) public virtual onlyVRROrOwner {
		vrrGeneratedRevenueTracker += _amount;
		lastVRRAmountReceived = _amount;

		_depositVST(_amount);
		emit VSTReceveidFromVRR(_amount);
	}

	function _depositVST(uint256 _amount) internal {
		if (_amount == 0) return;
		uint256 totalVST = _spSupply();

		uint256 secondDifference = (block.timestamp - lastUpdate);
		uint256 maxRewards = FullMath.mulDiv(_amount, allocationBPS, BPS);
		uint256 minRewards = _getMaxRatePerSecond(totalVST, BPS) *
			secondDifference;
		uint256 toSavingModule = maxRewards < minRewards
			? maxRewards
			: minRewards;

		if (interestCapBPS >= BPS && totalVST > 0) {
			toSavingModule = maxRewards;
		}

		if (toSavingModule < _amount) {
			IERC20(vst).transfer(emergencyReserve, _amount - toSavingModule);
		}

		if (toSavingModule == 0) return;

		rewardAllocation += toSavingModule;
		lastUpdate = block.timestamp;
		lastVRRRatePerSecond = toSavingModule / secondDifference;

		if (totalWeight > 0) share += FullMath.rdiv(_crop(), totalWeight);

		stock = rewardAllocation;

		emit PoolUpdated(toSavingModule, rewardAllocation);
	}

	function createLock(
		uint256 _lockTime,
		uint256 _amount,
		bool _autoLock
	) external {
		if (_spSupply() + _amount > maxVST) revert PoolIsFull();
		if (_amount == 0) revert AmountIsZero();
		if (_lockTime > maxLockDays || _lockTime == 0) {
			revert InvalidLockTime();
		}
		IInterestManager(vrrManager).updateModules();

		uint256 newShare = 1e18;

		if (totalWeight > 0) {
			newShare = (totalWeight * _amount) / _spSupply();
		}

		uint256 lockId = locks.length;
		stabilityPool.provideToSP(msg.sender, lockId, _amount);

		locks.push(
			Lock({
				user: msg.sender,
				autoLock: _autoLock,
				lockDays: uint128(_lockTime),
				claimed: 0,
				end: uint128(block.timestamp + (_lockTime * 1 days)),
				initialAmount: uint128(_amount),
				cappedShare: uint128(FullMath.mulDiv(_lockTime, BPS, maxLockDays)),
				lastTimeClaimed: block.timestamp
			})
		);

		userLocks[msg.sender].add(lockId);
		_addShare(lockId, newShare);

		emit LockCreated(msg.sender, lockId, _lockTime, _amount);
	}

	function claimAll(bool _removeExpired) external override {
		_multiClaim(userLocks[msg.sender].values(), _removeExpired);
	}

	function claimBatch(uint256[] calldata _ids, bool _removeExpired)
		public
		override
	{
		_multiClaim(_ids, _removeExpired);
	}

	function _multiClaim(uint256[] memory _ids, bool _removeExpired)
		internal
	{
		IInterestManager(vrrManager).updateModules();

		uint256 idsLength = _ids.length;

		if (idsLength == 0) revert EmptyArray();

		uint256 index = idsLength;
		uint256 lockId;
		Lock storage lock;

		while (index != 0) {
			index--;
			lockId = _ids[index];
			lock = locks[lockId];

			_claim(lockId, lock);

			if (_removeExpired) _exit(lockId, lock);
		}
	}

	function _claim(uint256 _lockId, Lock storage _lock) internal {
		if (_lock.user != msg.sender) revert NotLockOwner();
		_tryToAutolock(_lockId, _lock);

		uint256 newShare = 0;
		uint256 last = crops[_lockId];
		uint256 curr = FullMath.rmul(userShares[_lockId], share);
		uint256 lockBalance = stabilityPool.getCompoundedVSTDeposit(_lockId);
		bool lockExpired = !_lock.autoLock && _lock.end <= block.timestamp;

		if (curr <= last) return;

		if (totalWeight > 0 && lockBalance > 0) {
			newShare = FullMath.mulDiv(totalWeight, lockBalance, _spSupply());
		}

		uint256 rawInterest = curr - last;
		uint256 interest = FullMath.mulDiv(
			rawInterest,
			_lock.cappedShare,
			BPS
		);

		if (lockExpired) {
			interest = _sanitizeReward(_lock, lockBalance, interest);
		}

		uint256 missedInterest = rawInterest - interest;

		if (!_lock.autoLock) _lock.claimed += uint128(interest);

		_lock.lastTimeClaimed = block.timestamp;

		IERC20(vst).transfer(msg.sender, interest);

		if (missedInterest != 0) {
			IERC20(vst).transfer(emergencyReserve, missedInterest);
		}

		rewardAllocation -= rawInterest;
		stock = rewardAllocation;

		_partialExitShare(_lockId, newShare);
		emit UserClaimed(msg.sender, _lockId, interest);
	}

	function claimAllStabilityPool() external override {
		Set.UintSet storage allUserLocks = userLocks[msg.sender];

		uint256 length = allUserLocks.length();

		if (length == 0) revert EmptyArray();

		uint256 index = length;

		while (index != 0) {
			index--;
			stabilityPool.withdrawFromSP(msg.sender, allUserLocks.at(index), 0);
		}
	}

	function _sanitizeReward(
		Lock memory _lock,
		uint256 _compoundedVST,
		uint256 _reward
	) internal view returns (uint256) {
		if (_lock.lastTimeClaimed >= _lock.end || _lock.initialAmount == 0) {
			return 0;
		}
		uint256 maxReward = 0;

		uint256 secondSinceNowToLastClaim = block.timestamp -
			_lock.lastTimeClaimed;
		uint256 secondSinceEndToLastClaim = _lock.end - _lock.lastTimeClaimed;

		//prettier-ignore
		_reward = (_reward / secondSinceNowToLastClaim) * secondSinceEndToLastClaim;

		uint256 maxGain = _getMaxRatePerSecond(
			_compoundedVST,
			_lock.cappedShare
		) * (_lock.lockDays * 1 days);

		if (_lock.claimed < maxGain) {
			maxReward = maxGain - _lock.claimed;
		}

		if (maxReward < _reward) {
			_reward = maxReward;
		}

		return _reward;
	}

	function _getMaxRatePerSecond(uint256 _balance, uint256 _cappedShare)
		internal
		view
		returns (uint256 rate_)
	{
		rate_ = FullMath.mulDiv(_balance, interestCapBPS, BPS);

		if (_cappedShare != BPS) {
			rate_ = FullMath.mulDiv(rate_, _cappedShare, BPS);
		}

		rate_ /= 31557600;

		return rate_;
	}

	function exit(uint256 _lockId) external override {
		IInterestManager(vrrManager).updateModules();
		Lock storage lock = locks[_lockId];

		if (lock.user != msg.sender) revert NotLockOwner();

		_claim(_lockId, lock);
		_exit(_lockId, lock);
	}

	function _exit(uint256 _lockId, Lock storage _lock) internal {
		if (_lock.end > block.timestamp || _lock.autoLock) return;
		if (!userLocks[msg.sender].remove(_lockId)) {
			revert LockNotFoundOrExpired();
		}

		uint256 returningAmountLog = stabilityPool.getCompoundedVSTDeposit(
			_lockId
		);

		uint256 initialAmount = _lock.initialAmount;
		_lock.initialAmount = 0;

		stabilityPool.withdrawFromSP(msg.sender, _lockId, initialAmount);
		_exitShare(_lockId);

		emit ExitLock(msg.sender, _lockId, returningAmountLog);
	}

	function switchAutolock(uint256 _lockId, bool _active)
		external
		override
	{
		Lock storage lock = locks[_lockId];

		if (lock.user != msg.sender) revert NotLockOwner();

		IInterestManager(vrrManager).updateModules();

		_claim(_lockId, lock);

		if (_active && lock.end <= block.timestamp) {
			revert LockNotFoundOrExpired();
		}

		lock.autoLock = _active;

		emit LockAutoLockChanged(_lockId, _active);
	}

	function _tryToAutolock(uint256 _lockId, Lock storage _lock) internal {
		if (!_lock.autoLock || _lock.end > block.timestamp) return;

		uint128 newLockDays = _lock.lockDays;

		if (newLockDays > maxLockDays) {
			newLockDays = uint128(maxLockDays);
		}
		_updateLockWithNewDays(_lock, newLockDays);

		uint256 lockTimeInSeconds = _lock.lockDays * 1 days;

		uint256 missingEpoch = 1;
		missingEpoch += (block.timestamp - _lock.end) / lockTimeInSeconds;

		_lock.end += uint128((_lock.lockDays * missingEpoch) * 1 days);
		_lock.claimed = 0;

		emit LockAutoLockTriggered(_lockId, _lock.end);
	}

	function increaseLockDaysTo(uint256 _lockId, uint128 _lockDays)
		external
		override
	{
		if (_lockDays > maxLockDays || _lockDays == 0) {
			revert InvalidLockTime();
		}

		Lock storage lock = locks[_lockId];
		if (lock.user != msg.sender) revert NotLockOwner();

		if (lock.end <= block.timestamp && !lock.autoLock) {
			revert LockNotFoundOrExpired();
		}

		IInterestManager(vrrManager).updateModules();
		_claim(_lockId, lock);

		require(
			lock.lockDays < _lockDays,
			"You can only increase the lock period"
		);

		lock.end += uint128((_lockDays - lock.lockDays) * 1 days);
		_updateLockWithNewDays(lock, _lockDays);
	}

	function _updateLockWithNewDays(Lock storage _lock, uint128 _lockDays)
		internal
	{
		_lock.lockDays = _lockDays;

		_lock.cappedShare = uint128(
			FullMath.mulDiv(_lockDays, BPS, maxLockDays)
		);
	}

	function getUserLockIds(address _user)
		external
		view
		override
		returns (uint256[] memory)
	{
		return userLocks[_user].values();
	}

	function getCurrentLockReward(uint256 _lockId)
		external
		view
		override
		returns (uint256)
	{
		if (totalWeight == 0) return 0;

		return _getCurrentLockReward(_lockId, locks[_lockId]);
	}

	function _getCurrentLockReward(uint256 _lockId, Lock memory _lock)
		internal
		view
		returns (uint256 pendingReward_)
	{
		uint256 crop = rewardAllocation - stock;
		uint256 futureShare = share + FullMath.rdiv(crop, totalWeight);

		uint256 last = crops[_lockId];
		uint256 curr = FullMath.rmul(userShares[_lockId], futureShare);
		uint256 lockBalance = stabilityPool.getCompoundedVSTDeposit(_lockId);

		bool lockExpired = !_lock.autoLock && _lock.end <= block.timestamp;

		if (curr <= last) return 0;

		uint256 rawInterest = curr - last;
		uint256 interest = FullMath.mulDiv(
			rawInterest,
			_lock.cappedShare,
			BPS
		);

		if (lockExpired) {
			interest = _sanitizeReward(_lock, lockBalance, interest);
		}

		return interest;
	}

	function _spSupply() internal view returns (uint256) {
		return IERC20(vst).balanceOf(address(stabilityPool));
	}

	function _crop() internal view override returns (uint256) {
		return rewardAllocation - stock;
	}

	function getLocks() external view override returns (Lock[] memory) {
		return locks;
	}

	function getLockById(uint256 _lockId)
		external
		view
		override
		returns (Lock memory)
	{
		return locks[_lockId];
	}

	function setVRRManager(address _newVRRManager) external onlyOwner {
		vrrManager = _newVRRManager;
	}

	function setAllocation(uint16 _allocationBPS) external onlyOwner {
		allocationBPS = _allocationBPS;
	}

	function setInterestCap(uint16 _interestCapBPS) external onlyOwner {
		interestCapBPS = _interestCapBPS;
	}

	function setMaxLockDays(uint256 _maxDays) external onlyOwner {
		maxLockDays = _maxDays;
	}

	function setMaxSupply(uint256 _maxVST) external onlyOwner {
		maxVST = _maxVST;
	}

	function setEmergencyReserve(address _treasury) external onlyOwner {
		emergencyReserve = _treasury;
	}

	function withdrawOldVRR() external onlyOwner {
		IERC20(vst).transfer(
			emergencyReserve,
			IERC20(vst).balanceOf(address(this)) - rewardAllocation
		);
	}
}


