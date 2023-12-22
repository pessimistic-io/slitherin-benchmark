// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Initializable.sol";

/// @title SuperAdmin
/// @notice Supports the creation on a super admin role that can do specific actions
/// @dev There can only be one super admin account at a time
contract SuperAdmin is Initializable {
    /// @notice Address of the current super admin
    address public superAdmin;

    /// @notice Logs the information when the super admin is transferred
    event SuperAdminTransfer(address oldAdmin, address newAdmin);

    /// @notice Initializes the contract with the deployer as the initial super admin
    function initialize() external initializer {
        superAdmin = msg.sender;
    }

    /// @dev Throws an error if the caller is not the super admin
    /// @param caller The address of the caller
    modifier onlySuperAdmin(address caller) {
        require(caller == superAdmin, "NotSuperAdmin");
        _;
    }

    /// @notice Transfers the super admin role to a new address
    /// @param _superAdmin The address of the new super admin
    function transferSuperAdmin(address _superAdmin) external onlySuperAdmin(msg.sender) {
        emit SuperAdminTransfer(superAdmin, _superAdmin);
        superAdmin = _superAdmin;
    }

    /// @notice Checks if the caller is a valid super admin
    /// @param caller The address of the caller
    function isValidSuperAdmin(address caller) public view onlySuperAdmin(caller) {}

    uint256[60] private __gap;
}

