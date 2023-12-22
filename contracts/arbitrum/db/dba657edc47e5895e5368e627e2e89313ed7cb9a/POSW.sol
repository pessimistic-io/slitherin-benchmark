// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./AccessControl.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract ProofOfSocialWork is AccessControl, Ownable, ReentrancyGuard {

/** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    bytes32 public constant Claimer = keccak256("Claimer");

    bytes32 public constant Requestor = keccak256("Requestor");

    constructor(
        uint256 _version
    ) {  
        Version = _version;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

/** POSW Algorithm Version **/
    uint256 public Version;

    function updateVersion (uint256 newVersion) public onlyRole(Admin) {
        Version = newVersion;
    }

    mapping (uint256 => string) public Algorithm_POSW;

    function updateAlgorithm_POSW (uint256 batch, string memory URL_Algorithm_POSW) public onlyRole(Admin) {
        Algorithm_POSW[batch] = URL_Algorithm_POSW;
    }

/** Social Platforms **/
    string[] public SocialPlatforms = ["X", "Discord", "Youtube", "Telegram"];

    function updateSocialPlatforms (string memory newSocialPlatform) public onlyRole(Admin) {
        SocialPlatforms.push(newSocialPlatform);
    }

    mapping (uint256 => string) public Algorithm_SocialPlatforms;

    function updateAlgorithm_SocialPlatforms (uint256 batch, string memory URL_Algorithm_SocialPlatforms) public onlyRole(Admin) {
        Algorithm_SocialPlatforms[batch] = URL_Algorithm_SocialPlatforms;
    }

/***** POSW | Proof of Social Work *****/

/*** User POSW ***/
    struct _POSW {
        uint256 POSW_Overall;
        mapping (uint256 => uint256) POSW_Version; /* Version => POSW */
        mapping (uint256 => uint256) POSW_SocialPlatform; /* Social Platform => POSW */
        mapping (uint256 => uint256) POSW_Community; /* Community SBT => POSW */
        mapping (uint256 => mapping (uint256 => uint256)) POSW_Version_SocialPlatform; /* Version => Social Platform => POSW */
        mapping (uint256 => mapping (uint256 => uint256)) POSW_Version_Community; /* Verson => Community SBT => POSW */
        mapping (uint256 => mapping (uint256 => uint256)) POSW_SocialPlatform_Community; /* SocialPlatform => Community SBT => POSW */
        mapping (uint256 => mapping (uint256 => mapping (uint256 => uint256))) POSW_Version_SocialPlatform_Community; /* Verson => SocialPlatform => Community SBT => POSW */
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
        uint256 globalPOSW_Overall;
        mapping (uint256 => uint256) globalPOSW_Version; /* Version => Global POSW */
        mapping (uint256 => uint256) globalPOSW_SocialPlatform; /* Social Platform => Global POSW */
        mapping (uint256 => uint256) globalPOSW_Community; /* Community SBT => Global POSW */
        mapping (uint256 => mapping (uint256 => uint256)) globalPOSW_Version_SocialPlatform; /* Version => Social Platform => Global POSW */
        mapping (uint256 => mapping (uint256 => uint256)) globalPOSW_Version_Community; /* Verson => Community SBT => Global POSW */
        mapping (uint256 => mapping (uint256 => uint256)) globalPOSW_SocialPlatform_Community; /* SocialPlatform => Community SBT => Global POSW */
        mapping (uint256 => mapping (uint256 => mapping (uint256 => uint256))) globalPOSW_Version_SocialPlatform_Community; /* Verson => SocialPlatform => Community SBT => Global POSW */
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
    /* Internal Function */
    function addPOSW_User_Overall (address User, uint256 _POSW_Overall) internal {
        POSW[User].POSW_Overall += _POSW_Overall;
        POSW[User].POSW_Version[Version] += _POSW_Overall;
        globalPOSW.globalPOSW_Overall += _POSW_Overall;
        globalPOSW.globalPOSW_Version[Version] += _POSW_Overall;
    }

    function addPOSW_User_SocialPlatform (
        address User, 
        uint256[] memory Id_SocialPlatform, 
        uint256[] memory POSW_SocialPlatform
    ) internal {
        for (uint256 i=0; i<Id_SocialPlatform.length; i++) {
            POSW[User].POSW_SocialPlatform[Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
            POSW[User].POSW_Version_SocialPlatform[Version][Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
            globalPOSW.globalPOSW_SocialPlatform[Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
            globalPOSW.globalPOSW_Version_SocialPlatform[Version][Id_SocialPlatform[i]] += POSW_SocialPlatform[i];
        }
    }

    function addPOSW_User_Community (
        address User,
        uint256[] memory Id_Community,
        uint256[] memory POSW_Community
    ) internal {
        for (uint256 i=0; i<Id_Community.length; i++) {
            POSW[User].POSW_Community[Id_Community[i]] += POSW_Community[i];
            POSW[User].POSW_Version_Community[Version][Id_Community[i]] += POSW_Community[i];
            globalPOSW.globalPOSW_Community[Id_Community[i]] += POSW_Community[i];
            globalPOSW.globalPOSW_Version_Community[Version][Id_Community[i]] += POSW_Community[i];
        }
    }

    function addPOSW_User_SocialPlatform_Community (
        address User,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory Id_Community,
        uint256[][] memory POSW_SocialPlatform_Community
    ) internal {
        for (uint256 i=0; i<Id_SocialPlatform.length; i++) {
            for (uint256 j=0; j<Id_Community.length; j++) {
                POSW[User].POSW_SocialPlatform_Community[Id_SocialPlatform[i]][Id_Community[j]] += POSW_SocialPlatform_Community[i][j];
                POSW[User].POSW_Version_SocialPlatform_Community[Version][Id_SocialPlatform[i]][Id_Community[j]] += POSW_SocialPlatform_Community[i][j];
                globalPOSW.globalPOSW_SocialPlatform_Community[Id_SocialPlatform[i]][Id_Community[j]] += POSW_SocialPlatform_Community[i][j];
                globalPOSW.globalPOSW_Version_SocialPlatform_Community[Version][Id_SocialPlatform[i]][Id_Community[j]] += POSW_SocialPlatform_Community[i][j];
            }
        }
    }

    /* External Function */
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
