// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./AccessControl.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract ProofOfSocialWork is AccessControl, Ownable, ReentrancyGuard {

/** Roles **/

    bytes32 public constant Claimer = keccak256("Claimer"); /* Roles that can accumulate POSW */

    bytes32 public constant Requestor = keccak256("Requestor"); /* Roles that can request POSW */

    constructor(
        uint256 _version
    ) {  
        Version = _version;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Requestor, msg.sender);
    }

/** POSW Algorithm Version **/
    uint256 public Version; /* POSW algorithm could be updated in the future along with tech dev */

    function updateVersion (uint256 newVersion) public onlyOwner {
        Version = newVersion; /* POSW algorithm version updated only by Owner */
    }

    mapping (uint256 => string) public Algorithm_POSW; /* Reference for POSW algorithm doc */

    function updateAlgorithm_POSW (uint256 _version, string memory URL_Algorithm_POSW) public onlyOwner {
        Algorithm_POSW[_version] = URL_Algorithm_POSW; /* POSW algorithm doc updated only by Owner */
    }

/** Social Platform IDs **/
    mapping (uint256 => string) public socialPlatformID; /* Reference for Social Platform by IDs */

    function updateSocialPlatformID (uint256 batch, string memory newSocialPlatformID) public onlyOwner {
        socialPlatformID[batch] = newSocialPlatformID; /* Update Social Platform IDs only by Owner */
    }

/***** POSW | Proof of Social Work *****/

/*** User POSW ***/
    struct _POSW {
        uint256 POSW_Overall; /* User's total POSW */
        mapping (uint256 => uint256) POSW_Version; /* Version=>POSW | Recording User POSW by version */
        mapping (uint256 => uint256) POSW_SocialPlatform; /* SocialPlatformID=>POSW | Recording User POSW by SocialPlatform IDs */
        mapping (uint256 => uint256) POSW_Community; /* CommunityID=>POSW | Recording User POSW by Community IDs */
        mapping (uint256 => mapping (uint256 => uint256)) POSW_Version_SocialPlatform; /* Version=>SocialPlatformID=>POSW | Recording User POSW by version by SocialPlatform IDs */
        mapping (uint256 => mapping (uint256 => uint256)) POSW_Version_Community; /* Verson=>CommunityID=>POSW | Recording User POSW by version by Community IDs */
        mapping (uint256 => mapping (uint256 => uint256)) POSW_SocialPlatform_Community; /* SocialPlatformID=>CommunityID =>POSW | Recording User POSW by SocialPlatform IDs by Community IDs */
        mapping (uint256 => mapping (uint256 => mapping (uint256 => uint256))) POSW_Version_SocialPlatform_Community; /* Verson=>SocialPlatformID=>CommunityID=>POSW | Recording User POSW by version by SocialPlatform IDs by Community IDs */
    }

    mapping (address => _POSW) private POSW;

  /** User POSW Request **/
    /* User POSW Overall */
    function getPOSW (address User) external view onlyRole(Requestor) returns (uint256) {
        return POSW[User].POSW_Overall;
    }

    function getPOSWbyYourself () external view returns (uint256) {
        return POSW[msg.sender].POSW_Overall;
    }

    /* User POSW by Version */
    function getPOSW_Version (address User, uint256 _version) external view onlyRole(Requestor) returns (uint256) {
        return POSW[User].POSW_Version[_version];
    }

    function getPOSW_Version_Yourself (uint256 _version) external view returns (uint256) {
        return POSW[msg.sender].POSW_Version[_version];
    }

    /* User POSW by Social Platform */
    function getPOSW_SocialPlatform (address User, uint256 _socialPlatform) external view onlyRole(Requestor) returns (uint256) {
        return POSW[User].POSW_SocialPlatform[_socialPlatform];
    }

    function getPOSW_SocialPlatform_Yourself (uint256 _socialPlatform) external view returns (uint256) {
        return POSW[msg.sender].POSW_SocialPlatform[_socialPlatform];
    }

    /* User POSW by Community */
    function getPOSW_Community (address User, uint256 _community) external view onlyRole(Requestor) returns (uint256) {
        return POSW[User].POSW_Community[_community];
    }

    function getPOSW_Community_Yourself (uint256 _community) external view returns (uint256) {
        return POSW[msg.sender].POSW_Community[_community];
    }

    /* User POSW by Version & Social Platform */
    function getPOSW_Version_SocialPlatform (address User, uint256 _version, uint256 _socialPlatform) external view onlyRole(Requestor) returns (uint256) {
        return POSW[User].POSW_Version_SocialPlatform[_version][_socialPlatform];
    }

    function getPOSW_Version_SocialPlatform_Yourself (uint256 _version, uint256 _socialPlatform) external view returns (uint256) {
        return POSW[msg.sender].POSW_Version_SocialPlatform[_version][_socialPlatform];
    }

    /* User POSW by Version & Community */
    function getPOSW_Version_Community (address User, uint256 _version, uint256 _community) external view onlyRole(Requestor) returns (uint256) {
        return POSW[User].POSW_Version_Community[_version][_community];
    }

    function getPOSW_Version_Community_Yourself (uint256 _version, uint256 _community) external view returns (uint256) {
        return POSW[msg.sender].POSW_Version_Community[_version][_community];
    }

    /* User POSW by Social Platform & Community */
    function getPOSW_SocialPlatform_Community (address User, uint256 _socialPlatform, uint256 _community) external view onlyRole(Requestor) returns (uint256) {
        return POSW[User].POSW_SocialPlatform_Community[_socialPlatform][_community];
    }

    function getPOSW_SocialPlatform_Community_Yourself (uint256 _socialPlatform, uint256 _community) external view returns (uint256) {
        return POSW[msg.sender].POSW_SocialPlatform_Community[_socialPlatform][_community];
    }

    /* User POSW by Version & Social Platform & Community */
    function getPOSW_Version_SocialPlatform_Community (address User, uint256 _version, uint256 _socialPlatform, uint256 _community) external view onlyRole(Requestor) returns (uint256) {
        return POSW[User].POSW_Version_SocialPlatform_Community[_version][_socialPlatform][_community];
    }

    function getPOSW_Version_SocialPlatform_Community_Yourself (uint256 _version, uint256 _socialPlatform, uint256 _community) external view returns (uint256) {
        return POSW[msg.sender].POSW_Version_SocialPlatform_Community[_version][_socialPlatform][_community];
    }

  /** Global User POSW **/
    struct _globalPOSW {
        uint256 globalPOSW_Overall; /* Recording global User POSW */
        mapping (uint256 => uint256) globalPOSW_Version; /* Version=>globalPOSW | Recording Global User POSW by version */
        mapping (uint256 => uint256) globalPOSW_SocialPlatform; /* SocialPlatformID=>globalPOSW | Recording Global User POSW by Social Platform IDs */
        mapping (uint256 => uint256) globalPOSW_Community; /* CommunityID=>globalPOSW | Recording Global User POSW by Community IDs */
        mapping (uint256 => mapping (uint256 => uint256)) globalPOSW_Version_SocialPlatform; /* Version=>SocialPlatformID=>globalPOSW | Recording Global User POSW by version by SocialPlatform IDs */
        mapping (uint256 => mapping (uint256 => uint256)) globalPOSW_Version_Community; /* Verson=>CommunityID=>globalPOSW | Recording Global User POSW by version by Community IDs */
        mapping (uint256 => mapping (uint256 => uint256)) globalPOSW_SocialPlatform_Community; /* SocialPlatformID=>CommunityID=>globalPOSW | Recording Global User POSW by SocialPlatform IDs by Community IDs */
        mapping (uint256 => mapping (uint256 => mapping (uint256 => uint256))) globalPOSW_Version_SocialPlatform_Community; /* Verson=>SocialPlatformID=>CommunityID=>globalPOSW | Recording Global User POSW by version by SocialPlatform IDs by Community IDs */
    }

    _globalPOSW public globalPOSW;

  /** Global User POSW Request **/
    /* Global POSW Overall */
    function getGlobalPOSW_Overall () external view returns (uint256) {
        return globalPOSW.globalPOSW_Overall;
    }

    /* Global POSW by Version */
    function getGlobalPOSW_Version (uint256 _version) external view returns (uint256) {
        return globalPOSW.globalPOSW_Version[_version];
    }

    /* Global POSW by Social Platform */
    function getGlobalPOSW_SocialPlatform (uint256 _socialPlatform) external view returns (uint256) {
        return globalPOSW.globalPOSW_SocialPlatform[_socialPlatform];
    }

    /* Global POSW by Community */
    function getGlobalPOSW_Community (uint256 _community) external view onlyRole(Requestor) returns (uint256) {
        return globalPOSW.globalPOSW_Community[_community];
    }

    /* Global POSW by Version & Social Platform */
    function getGlobalPOSW_Version_SocialPlatform (uint256 _version, uint256 _socialPlatform) external view returns (uint256) {
        return globalPOSW.globalPOSW_Version_SocialPlatform[_version][_socialPlatform];
    }

    /* Global POSW by Version & Community */
    function getGlobalPOSW_Version_Community (uint256 _version, uint256 _community) external view onlyRole(Requestor) returns (uint256) {
        return globalPOSW.globalPOSW_Version_Community[_version][_community];
    }

    /* Global POSW by Social Platform & Community */
    function getGlobalPOSW_SocialPlatform_Community (uint256 _socialPlatform, uint256 _community) external view onlyRole(Requestor) returns (uint256) {
        return globalPOSW.globalPOSW_SocialPlatform_Community[_socialPlatform][_community];
    }

    /* Global POSW by Version & Social Platform & Community */
    function getGlobalPOSW_Version_SocialPlatform_Community (uint256 _version, uint256 _socialPlatform, uint256 _community) external view onlyRole(Requestor) returns (uint256) {
        return globalPOSW.globalPOSW_Version_SocialPlatform_Community[_version][_socialPlatform][_community];
    }


  /** User POSW On-Chain Accumulation **/
    /* Add user overall POSW & global overall POSW */
    function addPOSW_User_Overall (address User, uint256 _POSW_Overall) private {
        POSW[User].POSW_Overall += _POSW_Overall;
        POSW[User].POSW_Version[Version] += _POSW_Overall;
        globalPOSW.globalPOSW_Overall += _POSW_Overall;
        globalPOSW.globalPOSW_Version[Version] += _POSW_Overall;
    }

    /* Add user POSW by SocialPlatform IDs & global POSW by SocialPlatform IDs */
    function addPOSW_User_SocialPlatform (
        address User,
        uint256[] memory Id_SocialPlatform, 
        uint256[] memory POSW_SocialPlatform
    ) private {
        for (uint256 i=0; i<Id_SocialPlatform.length; i++) {
            POSW[User].POSW_SocialPlatform[Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
            POSW[User].POSW_Version_SocialPlatform[Version][Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
            globalPOSW.globalPOSW_SocialPlatform[Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
            globalPOSW.globalPOSW_Version_SocialPlatform[Version][Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
        }
    }

    /* Add user POSW by Community IDs & global POSW by Community IDs */
    function addPOSW_User_Community (
        address User,
        uint256[] memory Id_Community,
        uint256[] memory POSW_Community
    ) private {
        for (uint256 i=0; i<Id_Community.length; i++) {
            POSW[User].POSW_Community[Id_Community[i]] += POSW_Community[i];
            POSW[User].POSW_Version_Community[Version][Id_Community[i]] += POSW_Community[i];
            globalPOSW.globalPOSW_Community[Id_Community[i]] += POSW_Community[i];
            globalPOSW.globalPOSW_Version_Community[Version][Id_Community[i]] += POSW_Community[i];
        }
    }

    /* Add user POSW by SocialPlatform IDs by Community IDs & global POSW by SocialPlatform IDs by Community IDs */
    function addPOSW_User_SocialPlatform_Community (
        address User,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory Id_Community,
        uint256[][] memory POSW_SocialPlatform_Community
    ) private {
        for (uint256 i=0; i<Id_SocialPlatform.length; i++) {
            for (uint256 j=0; j<Id_Community.length; j++) {
                POSW[User].POSW_SocialPlatform_Community[Id_SocialPlatform[i]][Id_Community[j]] += POSW_SocialPlatform_Community[i][j];
                POSW[User].POSW_Version_SocialPlatform_Community[Version][Id_SocialPlatform[i]][Id_Community[j]] += POSW_SocialPlatform_Community[i][j];
                globalPOSW.globalPOSW_SocialPlatform_Community[Id_SocialPlatform[i]][Id_Community[j]] += POSW_SocialPlatform_Community[i][j];
                globalPOSW.globalPOSW_Version_SocialPlatform_Community[Version][Id_SocialPlatform[i]][Id_Community[j]] += POSW_SocialPlatform_Community[i][j];
            }
        }
    }

    /* Add POSW all-in-once | restricted by Claimer role only */
    function addPOSW_User (
        address User,
        uint256 POSW_Overall,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory Id_Community,
        uint256[] memory POSW_SocialPlatform,
        uint256[] memory POSW_Community,
        uint256[][] memory POSW_SocialPlatform_Community
    ) external onlyRole(Claimer) nonReentrant {
        addPOSW_User_Overall(User, POSW_Overall);
        addPOSW_User_SocialPlatform(User, Id_SocialPlatform, POSW_SocialPlatform);
        addPOSW_User_Community(User, Id_Community, POSW_Community);
        addPOSW_User_SocialPlatform_Community(User, Id_SocialPlatform, Id_Community, POSW_SocialPlatform_Community);
    }
}
