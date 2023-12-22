// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AccessControl.sol";

abstract contract LitterKittensAccessControl is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, _msgSender()), "LitterKittensAccessControl: Not admin.");
        _;
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "LitterKittensAccessControl: Not minter.");
        _;
    }

    modifier onlyBurner() {
        require(isBurner(_msgSender()), "LitterKittensAccessControl: Not burner.");
        _;
    }

    constructor() {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BURNER_ROLE, ADMIN_ROLE);

        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function addAdmin(address _addr) external onlyAdmin {
        grantRole(ADMIN_ROLE, _addr);
    }

    function addMinter(address _addr) external onlyAdmin {
        grantRole(MINTER_ROLE, _addr);
    }

    function addBurner(address _addr) external onlyAdmin {
        grantRole(BURNER_ROLE, _addr);
    }

    function removeAdmin(address _addr) external onlyAdmin {
        revokeRole(ADMIN_ROLE, _addr);
    }

    function removeMinter(address _addr) external onlyAdmin {
        revokeRole(MINTER_ROLE, _addr);
    }

    function removeBurner(address _addr) external onlyAdmin {
        revokeRole(BURNER_ROLE, _addr);
    }

    function isAdmin(address _addr) public view returns (bool) {
        return hasRole(ADMIN_ROLE, _addr);
    }

    function isMinter(address _addr) public view returns (bool) {
        return hasRole(MINTER_ROLE, _addr);
    }

    function isBurner(address _addr) public view returns (bool) {
        return hasRole(BURNER_ROLE, _addr);
    }
}

