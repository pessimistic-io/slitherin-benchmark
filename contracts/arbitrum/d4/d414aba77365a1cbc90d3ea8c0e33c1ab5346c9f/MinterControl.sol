// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./AccessControl.sol";

abstract contract MinterControl is AccessControl {
    bytes32 public constant SMOLCAR_OWNER_ROLE = keccak256("SMOLCAR_OWNER_ROLE");
    bytes32 public constant SMOLCAR_MINTER_ROLE = keccak256("SMOLCAR_MINTER_ROLE");

    modifier onlyOwner() {
        require(hasRole(SMOLCAR_OWNER_ROLE, _msgSender()), "MinterControl: not a SMOLCAR_OWNER_ROLE");
        _;
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "MinterControl: not a SMOLCAR_MINTER_ROLE");
        _;
    }

    constructor() {
        _setRoleAdmin(SMOLCAR_OWNER_ROLE, SMOLCAR_OWNER_ROLE);
        _setRoleAdmin(SMOLCAR_MINTER_ROLE, SMOLCAR_OWNER_ROLE);

        _setupRole(SMOLCAR_OWNER_ROLE, _msgSender());
    }

    function grantMinter(address _minter) external {
        grantRole(SMOLCAR_MINTER_ROLE, _minter);
    }

    function isMinter(address _minter) public view returns (bool) {
        return hasRole(SMOLCAR_MINTER_ROLE, _minter);
    }

    function grantOwner(address _owner) external {
        grantRole(SMOLCAR_OWNER_ROLE, _owner);
    }

    function isOwner(address _owner) public view returns (bool) {
        return hasRole(SMOLCAR_OWNER_ROLE, _owner);
    }
}

