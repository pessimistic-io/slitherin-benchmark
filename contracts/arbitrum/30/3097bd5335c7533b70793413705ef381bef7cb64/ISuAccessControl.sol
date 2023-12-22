// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAccessControlUpgradeable.sol";
import "./IERC165Upgradeable.sol";
import "./SuAccessRoles.sol";

/**
 * @notice Access control for contracts
 * @dev External interface of AccessControl declared to support ERC165 detection.
 **/
interface ISuAccessControl is IAccessControlUpgradeable, IERC165Upgradeable {
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
}

