//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IRandomizer.sol";
import "./AdminableUpgradeable.sol";
import "./IItemz.sol";
import "./IBugz.sol";
import "./IToadz.sol";
import "./IToadzMetadata.sol";
import "./IToadHousez.sol";
import "./IBadgez.sol";
import "./IWorld.sol";
import "./IWartlocksHallow.sol";
import "./IToadHousezMinter.sol";

abstract contract ToadHousezMinterState is Initializable, IToadHousezMinter, AdminableUpgradeable {

    event HouseBlueprintBugzCost(uint256 _bugzCost);
    event HouseBuildingBugzCost(uint256 _bugzCost);
    event HouseBuildingDuration(uint256 _duration);
    event BlueprintBuyingEnabledChanged(bool _isBlueprintBuyingEnabled);
    event HouseBuildingEnabledChanged(bool _isHouseBuildingEnabled);

    event HouseBuildingBatchStarted(address _user, uint256 _requestId, uint256 _numberOfHousesInBatch, uint256 _timeOfCompletion);
    event HouseBuildingBatchFinished(address _user, uint256 _requestId);

    IRandomizer public randomizer;
    IItemz public itemz;
    IBugz public bugz;
    IToadz public toadz;
    IToadzMetadata public toadzMetadata;
    IToadHousez public toadHousez;
    IBadgez public badgez;
    IWorld public world;
    IWartlocksHallow public wartlocksHallow;

    mapping(WoodType => uint256) public woodTypeToItemId;

    uint256 public houseBlueprintId;
    uint256 public houseBlueprintBugzCost;
    uint256 public houseBuildingBugzCost;
    uint256 public houseBuildingDuration;

    mapping(address => EnumerableSetUpgradeable.UintSet) internal addressToRequestIds;
    mapping(uint256 => RequestIdInfo) internal requestIdToHouses;

    // Rarities and aliases are used for the Walker's Alias algorithm.
    mapping(string => uint8[]) public traitTypeToRarities;
    mapping(string => uint8[]) public traitTypeToAliases;

    bool public isBlueprintBuyingEnabled;
    bool public isHouseBuildingEnabled;

    function __ToadHousezMinterState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        emit BlueprintBuyingEnabledChanged(false);
        emit HouseBuildingEnabledChanged(false);

        woodTypeToItemId[WoodType.PINE] = 3;
        woodTypeToItemId[WoodType.OAK] = 5;
        woodTypeToItemId[WoodType.REDWOOD] = 4;
        woodTypeToItemId[WoodType.BUFO_WOOD] = 6;
        woodTypeToItemId[WoodType.WITCH_WOOD] = 32;
        woodTypeToItemId[WoodType.TOAD_WOOD] = 7;
        woodTypeToItemId[WoodType.GOLD_WOOD] = 33;
        woodTypeToItemId[WoodType.SAKURA_WOOD] = 34;

        traitTypeToRarities[BACKGROUND] = [227, 155, 155, 155, 255, 155];
        traitTypeToAliases[BACKGROUND] = [4, 0, 0, 0, 0, 4];

        traitTypeToRarities[VARIATION] = [255, 254, 254];
        traitTypeToAliases[VARIATION] = [0, 0, 0];

        traitTypeToRarities[SMOKE] = [255, 255, 255, 255, 255, 255, 255, 255];
        traitTypeToAliases[SMOKE] = [0, 0, 0, 0, 0, 0, 0, 0];

        houseBlueprintId = 37;
        houseBlueprintBugzCost = 100 ether;
        emit HouseBlueprintBugzCost(houseBlueprintBugzCost);

        houseBuildingBugzCost = 0;
        emit HouseBuildingBugzCost(houseBuildingBugzCost);

        houseBuildingDuration = 1 days;
        emit HouseBuildingDuration(houseBuildingDuration);
    }
}

struct RequestIdInfo {
    uint256 startTime;
    BuildHouseParams[] houseParams;
}

struct BuildHouseParams {
    WoodType[5] woods;
}

struct HouseBuildingInfo {
    uint256 startTime;
    WoodType[5] woods;
}
