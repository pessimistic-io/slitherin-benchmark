// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Lock } from "./SavingModuleModel.sol";

interface ISavingModule {
	error NoPermission();
	error LockNotFoundOrExpired();
	error InvalidLockTime();
	error AmountIsZero();
	error EmptyArray();
	error NotLockOwner();
	error InvalidLock();
	error PoolIsFull();
	error LockStillRunning();

	event LockCreated(
		address indexed user,
		uint256 indexed lockId,
		uint256 time,
		uint256 initialAmount
	);
	event PoolUpdated(uint256 addedReward, uint256 totalAllocatedVST);
	event UserClaimed(
		address indexed user,
		uint256 indexed lockId,
		uint256 claimed
	);
	event LockAutoLockTriggered(uint256 indexed lockId, uint256 newEndTime);
	event ExitLock(
		address indexed user,
		uint256 indexed lockId,
		uint256 vstAmountReturned
	);

	event LockAutoLockChanged(uint256 indexed lockId, bool autolock);
	event VSTReceveidFromVRR(uint256 receivedVST);

	/**
	@notice createLock Deposit & Lock your vst into the system and start recolting rewards
	@param _lockTime How many days the vst will be locked (range: [1-90])
	@param _amount Quantity of VST
	@param _autoLock Does your lock auto-relock once the lock time is reached ? 
	 */
	function createLock(
		uint256 _lockTime,
		uint256 _amount,
		bool _autoLock
	) external;

	/**
	@notice claimBatch Claim rewards by lockIds
	@param _ids Unique id of the locks
	@param _removeExpired Remove any expired lock
	 */
	function claimBatch(uint256[] calldata _ids, bool _removeExpired)
		external;

	/**
	@notice claimAll Loop through all your locks and claim their rewards
	@param _removeExpired Remove any expired lock
	 */
	function claimAll(bool _removeExpired) external;

	/**
	@notice claimAllStabilityPool Claim all rewards from liquidation inside the Stability Pool
	 */
	function claimAllStabilityPool() external;

	/**
	@notice exit Withdraw the vst from an expired lock.
	@dev It also claims any pending rewards
	 */
	function exit(uint256 _lockId) external;

	/**
	@notice switchAutolock Enable or Disable the autolock on an active lock
	@param _lockId Unique Id of the lock
	@param _active New state of the autolock
	@dev You can't activate the autolock on an expired lock
	 */
	function switchAutolock(uint256 _lockId, bool _active) external;

	/**
	@notice getUserLockIds Get all lockIds of an user
	@param _user Address of the User
	 */
	function getUserLockIds(address _user)
		external
		view
		returns (uint256[] memory);

	/**
	@notice getCurrentLockReward Get pending VST rewards of a Lock
	@param _lockId Unique Id of the lock
	 */
	function getCurrentLockReward(uint256 _lockId)
		external
		view
		returns (uint256);

	/**
	@notice depositVST Operation Fucntion allowing to deposit VST later used as reward
	@param _amount the quantity of vst
	@dev Can only be used by Admin Gnosis & InterestRateManager
	 */
	function depositVST(uint256 _amount) external;

	// /**
	// @notice getPendingAllocation Get the total available reward of the system for yield farming
	// @return pendingAllocation_ pending allocation used for yield farming
	//  */
	// function getPendingAllocation() external view returns (uint256);

	/**
	@notice getLocks get All locks in the system
	@return locks_ All lock datas
	 */
	function getLocks() external view returns (Lock[] memory);

	/**
	@notice getLockById Get Lock info with its Unique Id
	@param _lockId Unique Id of the lock
	 */
	function getLockById(uint256 _lockId)
		external
		view
		returns (Lock memory);
}


