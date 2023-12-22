// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AccessControlEnumerableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";


/**
 * @dev Manager role for all contracts of USD+
 * Single point for assigning roles
 * Allow to set role in this place and this will be available for other contracts
 */

contract RoleManager is Initializable, AccessControlEnumerableUpgradeable, UUPSUpgradeable {

    bytes32 public constant PORTFOLIO_AGENT_ROLE = keccak256("PORTFOLIO_AGENT_ROLE");
    bytes32 public constant UNIT_ROLE = keccak256("UNIT_ROLE");
    bytes32 public constant FREE_RIDER_ROLE = keccak256("FREE_RIDER_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");

    // ---  constructor

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _setRoleAdmin(FREE_RIDER_ROLE, PORTFOLIO_AGENT_ROLE);
        _setRoleAdmin(UNIT_ROLE, PORTFOLIO_AGENT_ROLE);

        _grantRole(PORTFOLIO_AGENT_ROLE, 0x0bE3f37201699F00C21dCba18861ed4F60288E1D); // PM Agent
        _grantRole(PORTFOLIO_AGENT_ROLE, 0xe497285e466227F4E8648209E34B465dAA1F90a0); // OVN Treasure
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(DEFAULT_ADMIN_ROLE)
    override
    {}
}

