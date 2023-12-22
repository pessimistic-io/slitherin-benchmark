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

    function distributeEmissions() external;

    function stake(uint256 amount, uint16 lock) external returns (uint256);

    function addToStake(uint256 amount, uint256 stakeId) external;

    function unStake(uint256 stakeId) external;

    function unStakeAll() external;

    function claim(uint256 stakeId) external;

    function claimAll() external;

    function extendLockPeriod(uint256 stakeId, uint16 lock) external;

    function extendLockPeriodOfAllStakes(uint16 lock) external;

    function claimableById(uint256 stakeId) external view returns (uint256 total);

    function claimableByAddress(address account) external view returns (uint256 total);

    function getStakesOfAddress(address account) external view returns (uint256[] memory);

    function getStake(uint256 stakeId) external view returns (GFlyStake memory);

    function setPause(bool state) external;

    function setNextCron(uint256 nextCron_) external;
}

