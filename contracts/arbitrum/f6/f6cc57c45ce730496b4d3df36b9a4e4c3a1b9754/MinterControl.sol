// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./AccessControl.sol";

abstract contract MinterControl is AccessControl {
    bytes32 public constant SMOLPETS_OWNER_ROLE = keccak256("SMOLPETS_OWNER_ROLE");
    bytes32 public constant SMOLPETS_MINTER_ROLE = keccak256("SMOLPETS_MINTER_ROLE");

    modifier onlyOwner() {
        require(hasRole(SMOLPETS_OWNER_ROLE, _msgSender()), "MinterControl: not a SMOLPETS_OWNER_ROLE");
        _;
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "MinterControl: not a SMOLPETS_MINTER_ROLE");
        _;
    }

    constructor() {
        _setRoleAdmin(SMOLPETS_OWNER_ROLE, SMOLPETS_OWNER_ROLE);
        _setRoleAdmin(SMOLPETS_MINTER_ROLE, SMOLPETS_OWNER_ROLE);

        _setupRole(SMOLPETS_OWNER_ROLE, _msgSender());
    }

    function grantMinter(address _minter) external {
        grantRole(SMOLPETS_MINTER_ROLE, _minter);
    }

    function isMinter(address _minter) public view returns (bool) {
        return hasRole(SMOLPETS_MINTER_ROLE, _minter);
    }

    function grantOwner(address _owner) external {
        grantRole(SMOLPETS_OWNER_ROLE, _owner);
    }

    function isOwner(address _owner) public view returns (bool) {
        return hasRole(SMOLPETS_OWNER_ROLE, _owner);
    }
}

