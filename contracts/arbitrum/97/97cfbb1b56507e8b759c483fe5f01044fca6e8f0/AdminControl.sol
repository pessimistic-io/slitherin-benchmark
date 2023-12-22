// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./CommonErrors.sol";

abstract contract AdminControl is CommonErrors {

    address public admin; /// @notice The administrator for this contract.
    address public adminCandidate; /// @notice A proposed administrator candidate for this contract.

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _admin) {
        if (_admin == address(0)) revert AddressExpected();

        admin = _admin;
    }

    /**
     * @dev Emitted after an admin proposal is submitted.
     * @param currentAdmin The address of the previous admin
     * @param adminCandidate The address of the new admin
     */
    event ProposeAdmin(
        address currentAdmin,
        address adminCandidate
    );

    /**
     * @dev Emitted after the admin is updated.
     * @param oldAdmin The address of the previous admin
     * @param newAdmin The address of the new admin
     */
    event ChangeAdmin(
        address oldAdmin,
        address newAdmin
    );

    /**
     * @dev Verifies the current message sender is admin.
     */
    modifier onlyAdmin() {
        if(msg.sender != admin) revert OnlyAdmin();
        _;
    }

    /**
     * @dev Verifies the current message sender is admin.
     */
    modifier onlyAdminCandidate() {
        if(msg.sender != adminCandidate) revert OnlyAdminCandidate();
        _;
    }

    /**
     * @notice Proposese a new admin.
     * @param _adminCandidate The new admin being proposed.
     */
    function proposeAdmin(
        address _adminCandidate
    ) external onlyAdmin() {
        if (_adminCandidate == address(0)) revert AddressExpected();

        adminCandidate = _adminCandidate;

        emit ProposeAdmin(admin, _adminCandidate);
    }

    /**
     * @notice Revokes the proposed admin candidate.
     */
    function revokeCandidate() external onlyAdmin() {
        delete adminCandidate;
    }

    /**
     * @notice Called by the candidate to accept the role of admin.
     */
    function acceptAdministration() external onlyAdminCandidate() {
        emit ChangeAdmin(admin, adminCandidate);

        admin = adminCandidate;

        delete adminCandidate;
    }
}

