// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./State.sol";

contract Administration is State {
    address public projectAdmin;
    address public newProjectAdmin;
    address public platformAdmin;
    address public newPlatformAdmin;
    address payable public assetManager;
    
    modifier onlyProjectAdmin() {
        _isProjectAdmin();
        _;
    }

    function _isProjectAdmin() internal view {
        require(msg.sender == projectAdmin, "ONLY_PROJECT_ADMIN");
    }

    modifier onlyPlatformAdmin() {
        _isPlatformAdmin();
        _;
    }

    function _isPlatformAdmin() internal view {
        require(msg.sender == platformAdmin, "ONLY_PLATFORM_ADMIN");
    }

    modifier onlyAssetManager() {
        _isAssetManager();
        _;
    }

    function _isAssetManager() internal view {
        require(msg.sender == assetManager, "ONLY_ASSET_MANAGER");
    }

    function changeAssetManager(address payable newAssetManager) public onlyProjectAdmin onlyDuringInitialized{
        assetManager = newAssetManager;
    }

    function setNewProjectAdmin(address _newProjectAdmin) public onlyProjectAdmin {
        newProjectAdmin = _newProjectAdmin;
    }

    function changeProjectAdmin() public {
        require(msg.sender == newProjectAdmin, "ONLY_PROJECT_ADMIN");
        projectAdmin = newProjectAdmin;
    }

    function setNewPlatformAdmin(address _newPlatformAdmin) public onlyPlatformAdmin {
        newPlatformAdmin = _newPlatformAdmin;
    }

    function changePlatformAdmin() public {
        require(msg.sender == newPlatformAdmin, "ONLY_Platform_ADMIN");
        platformAdmin = newPlatformAdmin;
    }
}
