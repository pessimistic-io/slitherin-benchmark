// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./AccessControl.sol";

abstract contract AuthorizeAccess is AccessControl {
    bytes32 public constant AUTHORIZER_ROLE = keccak256("AUTHORIZER_ROLE");

    // Modifier for authorizer roles
    modifier onlyAuthorizer() {
        require(hasRole(AUTHORIZER_ROLE, _msgSender()), "Not an authorizer");
        _;
    }
}

