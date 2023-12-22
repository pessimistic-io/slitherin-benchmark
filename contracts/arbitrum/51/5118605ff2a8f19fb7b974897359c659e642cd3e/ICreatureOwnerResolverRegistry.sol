// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

/**
 * @title  ICreatureOwnerResolverRegistry interface
 * @author Archethect
 * @notice This interface contains all functionalities for managing Creature owner resolvers
 */
interface ICreatureOwnerResolverRegistry {
    struct Creature {
        address ownerResolver;
        uint256 tokenId;
    }

    function isAllowed(address creatureOwnerResolver) external view returns (bool);

    function addCreatureOwnerResolver(address creatureOwnerResolver) external;

    function removeCreatureOwnerResolver(address creatureOwnerResolver) external;
}

