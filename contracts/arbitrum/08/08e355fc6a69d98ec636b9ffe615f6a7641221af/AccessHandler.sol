// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IAccessHandler.sol";
import "./BaseInitializer.sol";
import "./AccessControl.sol";
import "./Pausable.sol";

/**
 * @title Access Handler
 * @author Deepp Dev Team
 * @notice An access control contract. It restricts access to otherwise public
 *         methods, by checking for assigned roles. its meant to be extended
 *         and holds all the predefined role type for the derrived contracts.
 * @notice This is a util contract for the BookieMain app.
 */
abstract contract AccessHandler
    is IAccessHandler,
    BaseInitializer,
    AccessControl,
    Pausable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    bytes32 public constant BETTER_ROLE = keccak256("BETTER_ROLE");
    bytes32 public constant LOCKBOX_ROLE = keccak256("LOCKBOX_ROLE");
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 public constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant TOKEN_ROLE = keccak256("TOKEN_ROLE");
    bytes32 public constant BONUS_REPORTER_ROLE = keccak256("BONUS_REPORTER_ROLE");
    bytes32 public constant BONUS_CONTROLLER_ROLE = keccak256("BONUS_CONTROLLER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // TODO: Consider replacing OZ modifiers, cannot be overrriden.
    //       OZ implementation uses revert string instead of custom error.
    //       We could override the internal _ logic, but it feels invasive.

    /**
     * @notice Simple constructor, just sets the admin.
     * Allows for AccessHandler to be inherited by non-upgradeable contracts
     * that are normally deployed, with a contructor call.
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @notice Changes the admin and revokes the roles of the current admin.
     * @param newAdmin is the addresse of the new admin.
     */
    function changeAdmin(address newAdmin)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        // We only want 1 admin
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Puts the contract in pause state, for emergency control.
     */
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Puts the contract in operational state, after being paused.
     */
    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
