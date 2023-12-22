// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

contract AccessControls is OwnableUpgradeable, AccessControlUpgradeable {
  bytes32 public constant USER_ROLE = keccak256("USER_ROLE");

  struct UserRole {
    address userAddress;
    bytes32 role;
  }

  /// @notice adds new users and roles
  function addUserRoles(address[] memory userAddresses, bytes32 role) internal {
    for (uint256 index; index < userAddresses.length; index++) {
      if (role == "USER_ROLE") {
        _grantRole(USER_ROLE, userAddresses[index]);
      }
    }
  }

/// @notice removes new users and roles
  function revokeUserRoles(address[] memory userAddresses, bytes32 role) internal {
    for (uint256 index; index < userAddresses.length; index++) {
      if (role == "USER_ROLE") {
        _revokeRole(USER_ROLE, userAddresses[index]);
      }
    }
  }
}
