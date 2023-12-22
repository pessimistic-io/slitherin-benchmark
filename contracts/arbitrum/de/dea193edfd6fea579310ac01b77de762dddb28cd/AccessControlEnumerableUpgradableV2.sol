//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./AccessControlEnumerableUpgradeable.sol";
import "./Roles.sol";


contract AccessControlEnumerableUpgradableV2 is AccessControlEnumerableUpgradeable, Roles {

    function __AccessControlEnumerableV2_init() internal onlyInitializing {
        _grantRole(OWNER_ROLE, msg.sender);
        AccessControlEnumerableUpgradeable.__AccessControlEnumerable_init();
    }
    

    function grantRole(bytes32 _role, address _account) public override requiresEitherRole(ROLE_GRANTER_ROLE, OWNER_ROLE) {
        require(_role != OWNER_ROLE, "Cannot change owner role through grantRole");
        _grantRole(_role, _account);
    }

    function revokeRole(bytes32 _role, address _account) public override requiresEitherRole(ROLE_GRANTER_ROLE, OWNER_ROLE) {
        require(_role != OWNER_ROLE, "Cannot change owner role through grantRole");
        _revokeRole(_role, _account);
    }


    modifier requiresRole(bytes32 _role) {
        require(hasRole(_role, msg.sender), "Does not have required role");
        _;
    }

    modifier requiresEitherRole(bytes32 _roleOption1, bytes32 _roleOption2) {
        require(hasRole(_roleOption1, msg.sender) || hasRole(_roleOption2, msg.sender), "Does not have required role");
        _;
    }
}
