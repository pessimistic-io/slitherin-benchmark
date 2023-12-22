// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./MerkleProof.sol";
import "./ICreatureOwnerResolverRegistry.sol";

/**
 * @title  ISmolRingStaking interface
 * @author Archethect
 * @notice This interface contains all functionalities for staking Smol Rings.
 */
interface ISmolRingStaking {
    event Staked(ICreatureOwnerResolverRegistry.Creature creature, uint256[] rewards);
    event Unstaked(ICreatureOwnerResolverRegistry.Creature creature, uint256[] rewards);
    event Rewarded(ICreatureOwnerResolverRegistry.Creature creature, uint256[] rewards);
    event RewardTokenAdded(uint256 reward, address tokenDistributor, uint256 rewardsDuration);
    event RewardAdded(address tokenDistributor, uint256 reward);
    event RewardsDurationUpdated(address tokenDistributor, uint256 rewardsDuration);

    struct RewardTokenState {
        bool valid;
        uint256 rewardRatePerSecondInBPS;
        uint256 rewardPerTokenStored;
        uint256 lastRewardsRateUpdate;
        uint256 rewardsDuration;
        uint256 periodFinish;
        address tokenDistributor;
    }

    struct RewardCalculation {
        uint256 rewardFactor1;
        uint256 rewardFactor2;
        uint256 ring1Type;
        uint256 ring2Type;
    }

    function stake(
        uint256 ring1,
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        uint256 ring2,
        ICreatureOwnerResolverRegistry.Creature memory creature2,
        address ownerCreature1,
        address ownerCreature2
    ) external;

    function unstake(
        uint256 ring1,
        uint256 ring2,
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2,
        address ownerCreature1
    ) external;

    function withdrawRing(
        uint256 ring,
        ICreatureOwnerResolverRegistry.Creature memory creature,
        address ownerCreature
    ) external;

    function accrueForNewScore(ICreatureOwnerResolverRegistry.Creature memory creature) external;
}

