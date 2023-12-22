// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./AccessControl.sol";

abstract contract SharksAccessControl is AccessControl {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant REVEALER_ROLE = keccak256("REVEALER_ROLE");
    bytes32 public constant XP_MANAGER_ROLE = keccak256("XP_MANAGER_ROLE");

    modifier onlyOwner() {
        require(hasRole(OWNER_ROLE, _msgSender()), "SharksAccessControl: no OWNER_ROLE");
        _;
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "SharksAccessControl: no MINTER_ROLE");
        _;
    }

    modifier onlyRevealer() {
        require(isRevealer(_msgSender()), "SharksAccessControl: no REVEALER_ROLE");
        _;
    }

    modifier onlyXpManager() {
        require(isXpManager(_msgSender()), "SharksAccessControl: no XP_MANAGER_ROLE");
        _;
    }


    constructor() {
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(MINTER_ROLE, OWNER_ROLE);
        _setRoleAdmin(REVEALER_ROLE, OWNER_ROLE);
        _setRoleAdmin(XP_MANAGER_ROLE, OWNER_ROLE);

        _setupRole(OWNER_ROLE, _msgSender());
    }

    function grantOwner(address _owner) external onlyOwner {
        grantRole(OWNER_ROLE, _owner);
    }

    function grantXpManager(address _xpManager) external onlyOwner {
        grantRole(XP_MANAGER_ROLE, _xpManager);
    }

    function grantMinter(address _minter) external onlyOwner {
        grantRole(MINTER_ROLE, _minter);
    }
    function grantRevealer(address _revealer) external onlyOwner {
        grantRole(REVEALER_ROLE, _revealer);
    }

    function revokeOwner(address _owner) external onlyOwner {
        revokeRole(OWNER_ROLE, _owner);
    }

    function revokeXpManager(address _xpManager) external onlyOwner {
        revokeRole(XP_MANAGER_ROLE, _xpManager);
    }

    function revokeMinter(address _minter) external onlyOwner {
        revokeRole(MINTER_ROLE, _minter);
    }

    function revokeRevealer(address _revealer) external onlyOwner {
        revokeRole(REVEALER_ROLE, _revealer);
    }

    function isOwner(address _owner) public view returns (bool) {
        return hasRole(OWNER_ROLE, _owner);
    }

    function isXpManager(address _xpManager) public view returns (bool) {
        return hasRole(XP_MANAGER_ROLE, _xpManager);
    }

    function isRevealer(address _revealer) public view returns (bool) {
        return hasRole(REVEALER_ROLE, _revealer);
    }

    function isMinter(address _minter) public view returns (bool) {
        return hasRole(MINTER_ROLE, _minter);
    }

}
