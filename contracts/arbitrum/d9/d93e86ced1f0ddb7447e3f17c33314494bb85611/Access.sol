// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import { AccessControl } from "./AccessControl.sol";
import { Pausable } from "./Pausable.sol";

contract Access is AccessControl, Pausable {
    /**
     * {KEEPER_ROLE} - Stricly permissioned trustless access for off-chain programs or third party keepers.
     * {GUARDIAN_ROLE} - Role conferred to authors of the strategy, allows for tweaking non-critical params and emergency measures such as pausing and panicking.
     * {ADMIN}- Role can withdraw assets.
     * {DEFAULT_ADMIN_ROLE} (in-built access control role) This role would have the ability to grant any other roles.
     */
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(GUARDIAN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
    }

    function pause() external virtual onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external virtual onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}

