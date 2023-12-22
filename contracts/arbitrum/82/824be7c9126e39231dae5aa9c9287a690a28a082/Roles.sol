// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./AccessControlUpgradeable.sol";

abstract contract Roles is AccessControlUpgradeable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "NO");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "NA");
        _;
    }

    modifier onlyOperatorOrAdmin() {
        require(
            hasRole(OPERATOR_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "NW"
        );
        _;
    }

    modifier onlyAddressOrOperatorExcludeAdmin(address addressAllowed) {
        // Protect user deposits from abuse
        require(
            msg.sender == addressAllowed ||
                (hasRole(OPERATOR_ROLE, msg.sender) &&
                    !hasRole(ADMIN_ROLE, msg.sender)),
            "NW"
        );
        _;
    }
}

