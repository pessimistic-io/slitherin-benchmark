// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./AccessControl.sol";

abstract contract MinterControl is AccessControl {
    bytes32 public constant SMOLBODY_OWNER_ROLE = keccak256("SMOLBODY_OWNER_ROLE");
    bytes32 public constant SMOLBODY_MINTER_ROLE = keccak256("SMOLBODY_MINTER_ROLE");

    modifier onlyOwner() {
        require(hasRole(SMOLBODY_OWNER_ROLE, _msgSender()), "MinterControl: not a SMOLBODY_OWNER_ROLE");
        _;
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "MinterControl: not a SMOLBODY_MINTER_ROLE");
        _;
    }

    constructor() {
        _setRoleAdmin(SMOLBODY_OWNER_ROLE, SMOLBODY_OWNER_ROLE);
        _setRoleAdmin(SMOLBODY_MINTER_ROLE, SMOLBODY_OWNER_ROLE);

        _setupRole(SMOLBODY_OWNER_ROLE, _msgSender());
    }

    function grantMinter(address _minter) external {
        grantRole(SMOLBODY_MINTER_ROLE, _minter);
    }

    function isMinter(address _minter) public view returns (bool) {
        return hasRole(SMOLBODY_MINTER_ROLE, _minter);
    }

    function grantOwner(address _owner) external {
        grantRole(SMOLBODY_OWNER_ROLE, _owner);
    }

    function isOwner(address _owner) public view returns (bool) {
        return hasRole(SMOLBODY_OWNER_ROLE, _owner);
    }
}

