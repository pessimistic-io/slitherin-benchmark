// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";

import "./ICreatureOwnerResolverRegistry.sol";

/**
 * @title  CreatureOwnerResolverRegistry contract
 * @author Archethect
 * @notice This contract contains all functionalities for managing Creature owner resolvers
 */
contract CreatureOwnerResolverRegistry is Initializable, AccessControlUpgradeable, ICreatureOwnerResolverRegistry {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    mapping(address => bool) public registry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin_) public initializer {
        __AccessControl_init();
        require(address(admin_) != address(0), "CREATUREOWNERSRESOLVERREGISTRY:ILLEGAL_ADDRESS");
        _setupRole(ADMIN_ROLE, admin_);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "CREATUREOWNERSRESOLVERREGISTRY:ACCESS_DENIED");
        _;
    }

    function isAllowed(address creatureOwnerResolver) public view returns (bool) {
        return registry[creatureOwnerResolver];
    }

    function addCreatureOwnerResolver(address creatureOwnerResolver) public onlyAdmin {
        registry[creatureOwnerResolver] = true;
    }

    function removeCreatureOwnerResolver(address creatureOwnerResolver) public onlyAdmin {
        delete registry[creatureOwnerResolver];
    }
}

