// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;
import "./ICreatureOwnerResolverRegistry.sol";

/**
 * @title  IStakingHappinessBooster contract
 * @author Archethect
 * @notice This contract contains all functionalities for boosting happiness of Smols and staking Magic as requirement
 */
interface IStakingHappinessBooster {
    event HappinessBoosted(
        ICreatureOwnerResolverRegistry.Creature creature1,
        ICreatureOwnerResolverRegistry.Creature creature2,
        uint256 percentIncrease
    );

    function boostHappiness(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 percentageIncrease)
        external;

    function setMagicPricePerPercentInWei(uint256 magicPricePerPercentInWei_) external;
}

