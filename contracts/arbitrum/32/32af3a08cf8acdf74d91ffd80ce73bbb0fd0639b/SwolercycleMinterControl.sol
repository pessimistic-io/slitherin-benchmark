// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./AccessControl.sol";

abstract contract SwolercycleMinterControl is AccessControl {
    bytes32 public constant SWOLERCYCLE_OWNER_ROLE = keccak256("SWOLERCYCLE_OWNER_ROLE");
    bytes32 public constant SWOLERCYCLE_MINTER_ROLE = keccak256("SWOLERCYCLE_MINTER_ROLE");

    modifier onlyOwner() {
        require(hasRole(SWOLERCYCLE_OWNER_ROLE, _msgSender()), "SwolercycleMinterControl: not a SWOLERCYCLE_OWNER_ROLE");
        _;
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "SwolercycleMinterControl: not a SWOLERCYCLE_MINTER_ROLE");
        _;
    }

    constructor() {
        _setRoleAdmin(SWOLERCYCLE_OWNER_ROLE, SWOLERCYCLE_OWNER_ROLE);
        _setRoleAdmin(SWOLERCYCLE_MINTER_ROLE, SWOLERCYCLE_OWNER_ROLE);

        _setupRole(SWOLERCYCLE_OWNER_ROLE, _msgSender());
    }

    function grantMinter(address _minter) external {
        grantRole(SWOLERCYCLE_MINTER_ROLE, _minter);
    }

    function isMinter(address _minter) public view returns (bool) {
        return hasRole(SWOLERCYCLE_MINTER_ROLE, _minter);
    }

    function grantOwner(address _owner) external {
        grantRole(SWOLERCYCLE_OWNER_ROLE, _owner);
    }

    function isOwner(address _owner) public view returns (bool) {
        return hasRole(SWOLERCYCLE_OWNER_ROLE, _owner);
    }
}

