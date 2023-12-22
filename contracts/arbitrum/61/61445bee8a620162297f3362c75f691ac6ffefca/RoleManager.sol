// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./AccessControl.sol";

import "./IRoleManager.sol";

/// @title RoleManager manage the variety roles in huntnft system
/// @notice DO NOT SUPPORT L2 CROSS LAYER CALL
contract RoleManager is AccessControl, IRoleManager {
    /// @dev the role uuid of point operator
    bytes32 constant POINT_OPERATOR_ROLE = keccak256("POINT_OPERATOR_ROLE");
    /// @dev the role uuid of hunt nft store operator
    bytes32 constant STORE_OPERATOR_ROLE = keccak256("STORE_OPERATOR_ROLE");

    constructor() {
        /// @notice set sender to admin of roleManager
        AccessControl._setupRole(AccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setPointOperator(address _operator, bool _enabled) public {
        if (_enabled) {
            AccessControl.grantRole(POINT_OPERATOR_ROLE, _operator);
        } else {
            revokeRole(POINT_OPERATOR_ROLE, _operator);
        }
        emit PointOperatorSet(_operator, _enabled);
    }

    function isPointOperator(address _operator) public view returns (bool) {
        return hasRole(POINT_OPERATOR_ROLE, _operator);
    }

    function setStoreOperator(address _operator, bool _enabled) public {
        if (_enabled) {
            AccessControl.grantRole(STORE_OPERATOR_ROLE, _operator);
        } else {
            AccessControl.revokeRole(STORE_OPERATOR_ROLE, _operator);
        }
        emit StoreOperatorSet(_operator, _enabled);
    }

    function isStoreOperator(address _operator) public view returns (bool) {
        return AccessControl.hasRole(STORE_OPERATOR_ROLE, _operator);
    }
}

