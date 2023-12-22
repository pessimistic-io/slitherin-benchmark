// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./AccessControl.sol";
import "./Ownable.sol";
import "./IMetaX.sol";

contract AdminTools is AccessControl, Ownable {

/** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    constructor() {  
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

/** MetaX Smart Contracts **/
    address public socialMining_addr;

    address public builderIncentives_addr;

    address public earlyBirdUser_addr;

    address public earlyBirdBuilder_addr;

    function setAddr (
        address _socialMining_addr,
        address _builderIncentives_addr,
        address _earlyBirdUser_addr,
        address _earlyBirdBuilder_addr
    ) public onlyOwner {
        socialMining_addr = _socialMining_addr;
        builderIncentives_addr = _builderIncentives_addr;
        earlyBirdUser_addr = _earlyBirdUser_addr;
        earlyBirdBuilder_addr = _earlyBirdBuilder_addr;
    }

/** Daily Reset **/
    function dailyReset_Sept (
        bytes32 socialMining_root,
        bytes32 builderIncentives_root,
        bytes32 earlyBirdUser_Ini_root,
        bytes32 earlyBirdUser_Claim_root,
        bytes32 earlyBirdBuilder_Ini_root
    ) public onlyRole(Admin) {
        IMetaX(socialMining_addr).dailyReset(socialMining_root);
        IMetaX(builderIncentives_addr).dailyReset(builderIncentives_root);
        IMetaX(earlyBirdUser_addr).setRoot_Ini(earlyBirdUser_Ini_root);
        IMetaX(earlyBirdUser_addr).setRoot_Claim(earlyBirdUser_Claim_root);
        IMetaX(earlyBirdBuilder_addr).setRoot_Ini(earlyBirdBuilder_Ini_root);
    }

    function dailyReset_2024 (
        bytes32 socialMining_root,
        bytes32 builderIncentives_root,
        bytes32 earlyBirdUser_Claim_root
    ) public onlyRole(Admin) {
        IMetaX(socialMining_addr).dailyReset(socialMining_root);
        IMetaX(builderIncentives_addr).dailyReset(builderIncentives_root);
        IMetaX(earlyBirdUser_addr).setRoot_Claim(earlyBirdUser_Claim_root);
    }

    function dailyReset_normal (
        bytes32 socialMining_root,
        bytes32 builderIncentives_root
    ) public onlyRole(Admin) {
        IMetaX(socialMining_addr).dailyReset(socialMining_root);
        IMetaX(builderIncentives_addr).dailyReset(builderIncentives_root);
    }
}
