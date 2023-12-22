// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./Initializable.sol";
import "./AccessControlEnumerable.sol";

abstract contract Access is AccessControlEnumerable, Initializable {
    bytes32 public constant GOVERNOR_ROLE = keccak256("LC_GOVERNOR");
    bytes32 public constant OPERATOR_ROLE = keccak256("LC_OPERATOR");

    // solhint-disable-next-line func-name-mixedcase
    function __Access_init(address granteeAddress_) internal onlyInitializing {
        _setRoleAdmin(GOVERNOR_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, OPERATOR_ROLE);
        _grantRole(GOVERNOR_ROLE, granteeAddress_);
        _grantRole(OPERATOR_ROLE, granteeAddress_);
    }

    modifier onlyGovernor() {
        require(hasRole(GOVERNOR_ROLE, msg.sender), "LC:CALLER_NOT_GOVERNOR");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "LC:CALLER_NOT_OPERATOR");
        _;
    }

    uint256[48] private __gap;
}

