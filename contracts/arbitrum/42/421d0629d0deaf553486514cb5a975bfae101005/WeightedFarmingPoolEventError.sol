// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

abstract contract WeightedFarmingPoolEventError {
    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event PoolAdded(uint256 poolId, address token);
    event NewTokenAdded(
        uint256 indexed poolId,
        address token,
        uint256 index,
        uint256 weight
    );
    event PoolUpdated(uint256 indexed poolId, uint256 accRewardPerShare);
    event Harvest(
        uint256 indexed poolId,
        address indexed user,
        address indexed receiver,
        uint256 reward
    );
    event PoolWeightUpdated(
        uint256 indexed poolId,
        uint256 index,
        uint256 newWeight
    );
    event RewardSpeedUpdated(
        uint256 indexed poolId,
        uint256 newSpeed,
        uint256[] yearsUpdated,
        uint256[] monthsUpdateed
    );

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error WeightedFarmingPool_ZeroAddress();
    error WeightedFarmingPool__AlreadySupported();
    error WeightedFarmingPool__WrongDateLength();
    error WeightedFarmingPool__ZeroAmount();
    error WeightedFarmingPool__InexistentPool();
    error WeightedFarmingPool__OnlyPolicyCenter();
    error WeightedFarmingPool__NotInPool();
    error WeightedFarmingPool__NotEnoughAmount();
    error WeightedFarmingPool__NotSupported();
}

