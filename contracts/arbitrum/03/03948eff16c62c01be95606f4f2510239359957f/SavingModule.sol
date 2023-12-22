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
	uint256 public interestMinted;

	uint16 public allocationBPS;
	uint16 public interestCapBPS;

	uint256 public lastUpdate;
	uint256 public releaseDate; // Unused

	Lock[] internal locks;
	mapping(address => Set.UintSet) private userLocks;

	address public emergencyReserve;

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

	function depositVST(uint256 _amount) external onlyVRROrOwner {
		vrrGeneratedRevenueTracker += _amount;

		_depositVST(_amount);
		emit VSTReceveidFromVRR(_amount);
	}

	function _depositVST(uint256 _amount) internal {
		uint256 reward = _getRewardToRefill(_amount);

		if (reward < _amount) {
			IERC20(vst).transfer(emergencyReserve, _amount - reward);
		}

		rewardAllocation += reward;

		if (reward != 0) {
			emit PoolUpdated(reward, rewardAllocation);
		}

		_updateReward();
	}

	function _getRewardToRefill(uint256 vrrAdded)
		internal
		view
		returns (uint256)
	{
		uint256 maxRewards = FullMath.mulDiv(vrrAdded, allocationBPS, BPS);
		uint256 minRewards = FullMath.mulDiv(_spSupply(), interestCapBPS, BPS);
		uint256 currentAllocation = rewardAllocation;

		uint256 reward = maxRewards < minRewards ? maxRewards : minRewards;
		return (currentAllocation >= reward) ? 0 : reward - currentAllocation;
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
		_updateReward();

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

		if (totalWeight > 0) {
			share = share + FullMath.rdiv(_crop(), totalWeight);
		}

		_tryToAutolock(_lockId, _lock);

		uint256 newShare = 0;
		uint256 last = crops[_lockId];
		uint256 curr = FullMath.rmul(userShares[_lockId], share);
		uint256 lockBalance = stabilityPool.getCompoundedVSTDeposit(_lockId);
		bool lockExpired = !_lock.autoLock && _lock.end <= block.timestamp;

		if (curr <= last) {
			return;
		}
		if (totalWeight > 0 && lockBalance > 0 && !lockExpired) {
			newShare = (totalWeight * lockBalance) / _spSupply();
		}

		uint256 rawInterest = curr - last;
		interestMinted -= rawInterest;

		uint256 interest = FullMath.mulDiv(
			rawInterest,
			_lock.cappedShare,
			BPS
		);

		if (lockExpired) {
			interest = _sanitizeReward(_lock, lockBalance, interest);
		}

		if (!_lock.autoLock) _lock.claimed += uint128(interest);

		_lock.lastTimeClaimed = block.timestamp;

		IERC20(vst).transfer(msg.sender, interest);
		_depositVST(rawInterest - interest);

		emit UserClaimed(msg.sender, _lockId, interest);

		stock = interestMinted;
		_partialExitShare(_lockId, newShare);
	}

	function _sanitizeReward(
		Lock memory _lock,
		uint256 _compoundedVST,
		uint256 _reward
	) internal view returns (uint256) {
		if (_lock.lastTimeClaimed >= _lock.end) return 0;

		uint256 maxGain = _getMaxLockSettingRewards(_compoundedVST, _lock);
		uint256 maxReward = 0;

		if (_lock.claimed < maxGain) {
			maxReward = maxGain - _lock.claimed;
		}

		if (maxReward < _reward) {
			_reward = maxReward;
		}

		return _reward;
	}

	function _getMaxLockSettingRewards(
		uint256 _vstBalance,
		Lock memory _lock
	) internal view returns (uint256 maxGain_) {
		maxGain_ = FullMath.mulDiv(_vstBalance, interestCapBPS, BPS);

		maxGain_ = FullMath.mulDiv(maxGain_, _lock.cappedShare, BPS);
		maxGain_ = _compound(
			maxGain_,
			((_lock.lockDays * 1 days) / 1 minutes) * YEAR_MINUTE
		);

		return maxGain_;
	}

	function exit(uint256 _lockId) external override {
		_updateReward();

		Lock storage lock = locks[_lockId];

		if (lock.user != msg.sender) revert NotLockOwner();

		_claim(_lockId, lock);
		_exit(_lockId, lock);
	}

	function switchAutolock(uint256 _lockId, bool _active)
		external
		override
	{
		_updateReward();

		Lock storage lock = locks[_lockId];

		if (lock.user != msg.sender) revert NotLockOwner();

		_claim(_lockId, lock);

		if (_active && lock.end <= block.timestamp) {
			revert LockNotFoundOrExpired();
		}

		lock.autoLock = _active;

		if (_active) _tryToAutolock(_lockId, lock);

		emit LockAutoLockChanged(_lockId, _active);
	}

	function _tryToAutolock(uint256 _lockId, Lock storage _lock) internal {
		if (!_lock.autoLock || _lock.end > block.timestamp) return;

		uint256 lockTimeInSeconds = _lock.lockDays * 1 days;

		uint256 missingEpoch = 1;
		missingEpoch += (block.timestamp - _lock.end) / lockTimeInSeconds;

		_lock.end += uint128((_lock.lockDays * missingEpoch) * 1 days);

		if (missingEpoch > 1) _lock.claimed = 0;

		emit LockAutoLockTriggered(_lockId, _lock.end);
	}

	function _updateReward() internal {
		uint256 minuteDifference = (block.timestamp - lastUpdate) / 1 minutes;

		if (minuteDifference == 0) return;

		lastUpdate = block.timestamp;

		uint256 interest = _compound(
			rewardAllocation,
			minuteDifference * YEAR_MINUTE
		);

		interestMinted += interest;
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
		return _getCurrentLockReward(_lockId, locks[_lockId]);
	}

	function _getCurrentLockReward(uint256 _lockId, Lock memory _lock)
		internal
		view
		returns (uint256 pendingReward_)
	{
		if (totalWeight == 0) return 0;

		uint256 minuteDifference = (block.timestamp - lastUpdate) / 1 minutes;
		uint256 futureInterestMinted = interestMinted;
		if (minuteDifference != 0) {
			futureInterestMinted += _compound(
				rewardAllocation,
				minuteDifference * YEAR_MINUTE
			);
		}

		uint256 crop = futureInterestMinted - stock;
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

	function _compound(uint256 reward, uint256 _timeInYear)
		internal
		pure
		returns (uint256)
	{
		return
			FullMath.mulDiv(
				reward,
				intoUint256(ud(2e18).pow(ud(_timeInYear))),
				1e18
			) - reward;
	}

	function _spSupply() internal view returns (uint256) {
		return IERC20(vst).balanceOf(address(stabilityPool));
	}

	function _crop() internal view override returns (uint256) {
		return interestMinted - stock;
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


