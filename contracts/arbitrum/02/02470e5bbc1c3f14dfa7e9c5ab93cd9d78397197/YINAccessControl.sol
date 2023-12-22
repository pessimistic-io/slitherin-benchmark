// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "./AccessControl.sol";
import "./StringA.sol";

abstract contract YINAccessControl is AccessControl {
    bytes32 public constant STRATEGY_OPERATOR = keccak256("STRATEGY_OPERATOR");
    bytes32 public constant STRATEGY_CONTRACT = keccak256("STRATEGY_CONTRACT");

    modifier onlyRoleOrAdmin(bytes32 role) {
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            _checkRole(role, _msgSender());
        }
        _;
    }

    modifier onlyRole(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        StringA.toHexString(uint160(account), 20),
                        " is missing role ",
                        StringA.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }
}

