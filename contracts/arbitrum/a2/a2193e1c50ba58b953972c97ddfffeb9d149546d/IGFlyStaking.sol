// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./GFly.sol";

interface IGFlyStaking {
    struct GFlyStake {
        address owner;
        uint256 amount;
        uint16 lock;
        uint16 unlockEpoch;
        uint256 pendingRewards;
        uint16 lastProcessEpoch;
        bool autoIncreaseLock;
    }

    event Staked(address indexed account, uint256 indexed stakeId, uint256 amount, uint16 lock, uint16 unlockEpoch);
    event UnStaked(address indexed account, uint256 indexed stakeId, uint256 amount);
    event StakeTransfered(
        address indexed owner,
        uint256 indexed stakeId,
        address indexed newOwner,
        uint256 newStakeId,
        uint256 amount
    );
    event LockExtended(address indexed account, uint256 indexed stakeId, uint16 lock, uint16 unlockEpoch);
    event Claimed(address indexed account, uint256 indexed stakeId, uint256 amount);
    event ClaimedAndRestaked(address indexed account, uint256 indexed stakeId, uint256 amount);
    event Paused(bool state);
    event EmissionsDistributed(uint256 totalMiningPower, uint16 currentEpoch);
    event AutoIncreaseLockToggled(address indexed account, uint256 indexed stakeId, bool enable);

    function distributeEmissions() external;

    function stake(uint256 amount, uint16 lock) external returns (uint256);

    function addToStake(uint256 amount, uint256 stakeId) external;

    function unStake(uint256 stakeId) external;

    function unStakeAll() external;

    function unStakeBatch(uint256[] memory stakeIds) external;

    function claim(uint256 stakeId) external;

    function claimAll() external;

    function claimBatch(uint256[] memory stakeIds) external;

    function extendLockPeriod(uint256 stakeId, uint16 lock) external;

    function extendLockPeriodOfAllStakes(uint16 lock) external;

    function extendLockPeriodOfBatchStakes(uint16 lock, uint256[] memory stakeIds) external;

    function claimableById(uint256 stakeId) external view returns (uint256 total);

    function claimableByAddress(address account) external view returns (uint256 total);

    function getStakesOfAddress(address account) external view returns (uint256[] memory);

    function getStake(uint256 stakeId) external view returns (GFlyStake memory);

    function balanceOf(address account) external view returns (uint256);

    function setPause(bool state) external;

    function setNextCron(uint256 nextCron_) external;

    function setPendingEmissionsOfStake(uint256 stakeId, uint256 pendingRewards) external;

    function autoIncreaseLock(uint256 stakeId, bool enable) external;

    function autoIncreaseLockOfAllStakes(bool enable) external;

    function autoIncreaseLockOfBatchStakes(bool enable, uint256[] memory stakeIds) external;
}

