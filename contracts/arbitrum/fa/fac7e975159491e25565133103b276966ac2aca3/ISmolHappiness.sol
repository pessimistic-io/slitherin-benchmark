// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;
import "./ICreatureOwnerResolverRegistry.sol";

/**
 * @title  ISmolHappiness interface
 * @author Archethect
 * @notice This interface contains all functionalities for Smol happiness.
 */
interface ISmolHappiness {
    struct Happiness {
        bool valid;
        uint256 score;
        uint256 lastModified;
    }

    function getCurrentHappiness(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (uint256);

    function getStartHappiness(ICreatureOwnerResolverRegistry.Creature memory creature) external view returns (uint256);

    function setHappiness(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 happiness) external;

    function increaseHappiness(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 happiness) external;

    function decreaseHappiness(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 happiness) external;

    function enableHappiness() external;

    function disableHappiness() external;

    function setDecayFactor(uint256 decay) external;

    function getHappinessDecayPerSec() external view returns (uint256);

    function getMaxHappiness() external view returns (uint256);
}

