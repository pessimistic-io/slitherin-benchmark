// SPDX-License-Identifier: MIT
/**
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(     (@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(   @@@@@@@@@@@@@@@@@@@@(            @@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@         @@@@@@@@@@@@@@@             @@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @@@@@@@@@@@(            @@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@      @@@@@@@@@@@@             @@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@(            @@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@     @@@@@@@     @@@@@@@             @@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@(         @@(         @@(            @@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@          @@          @@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@     @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@ @@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(     @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @           @           @@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@(            @@@         @@@         @@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@             @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@(            @@@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@             @@@@@@@@@@@       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@(            @@@@@@@@@@@@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@             @@@@@@@@@@@@@@@         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@(            @@@@@@@@@@@@@@@@@@@@@   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@(     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 */
pragma solidity 0.8.11;

import "./AccessControlUpgradeable.sol";

contract NilRolesUpgradeable is Initializable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER");

    address public _owner;
    address public operator;
    address public admin;
    address public signer;

    function __NilRoles_init(
        address owner_,
        address admin_,
        address operator_,
        address signer_
    ) internal onlyInitializing {
        __AccessControl_init_unchained();
        __NilRoles_init_unchained(owner_, admin_, operator_, signer_);
    }

    function __NilRoles_init_unchained(
        address owner_,
        address admin_,
        address operator_,
        address signer_
    ) internal onlyInitializing {
        require(owner_ != address(0), "NIL:INVALID_OWNER_ADDRESS");
        require(admin_ != address(0), "NIL:INVALID_ADMIN_ADDRESS");
        require(operator_ != address(0), "NIL:INVALID_OPERATOR_ADDRESS");
        require(signer_ != address(0), "NIL:INVALID_SIGNER_ADDRESS");
        _owner = owner_;
        admin = admin_;
        operator = operator_;
        signer = signer_;

        _setupRole(ADMIN_ROLE, admin);
        _setupRole(OPERATOR_ROLE, admin);
        _setupRole(OPERATOR_ROLE, operator);
        _setupRole(OWNER_ROLE, admin);
        _setupRole(OWNER_ROLE, _owner);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setupRole(SIGNER_ROLE, signer);
        _setRoleAdmin(SIGNER_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "NIL:ACCESS_DENIED");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "NIL:ACCESS_DENIED");
        _;
    }

    modifier onlySigner() {
        require(hasRole(SIGNER_ROLE, msg.sender), "NIL:ACCESS_DENIED");
        _;
    }

    modifier onlyOwner() {
        require(hasRole(OWNER_ROLE, msg.sender), "NIL:ACCESS_DENIED");
        _;
    }
}

