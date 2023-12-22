//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IRandomizer.sol";
import "./AdminableUpgradeable.sol";
import "./IPilgrimage.sol";
import "./ILegion.sol";
import "./ILegionMetadataStore.sol";
import "./IStarlightTemple.sol";
import "./ILegion1155.sol";

abstract contract PilgrimageState is Initializable, IPilgrimage, AdminableUpgradeable {

    event PilgrimagesStarted(
        address indexed _user,
        address indexed _legionContract,
        uint256 indexed _finishTime,
        uint256[] _ids1155,
        uint256[] _amounts1155,
        uint256[] _pilgrimageIds);
    event NoPilgrimagesToFinish(address indexed _user);
    event PilgrimagesFinished(address indexed _user, uint256[] _tokenIds, uint256[] _finishedPilgrimageIds);

    IRandomizer public randomizer;
    ILegion public legion;
    ILegionMetadataStore public legionMetadataStore;
    ILegion1155 public legion1155;
    ILegion1155 public legionGenesis1155;
    IStarlightTemple public starlightTemple;

    EnumerableSetUpgradeable.UintSet internal legion1155Ids;
    // The 1155 id of the legion to the rarity it will map to.
    mapping(uint256 => LegionRarity) public legionIdToRarity;
    mapping(uint256 => LegionClass) public legionIdToClass;
    mapping(uint256 => uint256) public legionIdToChanceConstellationUnlocked;
    mapping(uint256 => uint8) public legionIdToNumberConstellationUnlocked;

    // Represents a single pilgrimage by 1 legion1155 id with an amount of 1.
    uint256 public pilgrimageID;
    mapping(address => EnumerableSetUpgradeable.UintSet) internal userToPilgrimagesInProgress;

    mapping(uint256 => uint256) public pilgrimageIdToStartTime;
    mapping(uint256 => LegionRarity) public pilgrimageIdToRarity;
    mapping(uint256 => LegionClass) public pilgrimageIdToClass;
    mapping(uint256 => LegionGeneration) public pilgrimageIdToGeneration;
    mapping(uint256 => uint256) public pilgrimageIdToOldId;
    // Pilgrimage ID -> Random number request ID.
    mapping(uint256 => uint256) public pilgrimageIdToRequestId;
    mapping(uint256 => uint256) public pilgrimageIdToChanceConstellationUnlocked;
    mapping(uint256 => uint8) public pilgrimageIdToNumberConstellationUnlocked;

    uint256 public pilgrimageLength;

    function __PilgrimageState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        pilgrimageID = 1;
        pilgrimageLength = 1 days;
    }
}
