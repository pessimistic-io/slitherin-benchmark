//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IRecruitLevel.sol";
import "./ILegionMetadataStore.sol";
import "./ILegion.sol";
import "./IConsumable.sol";
import "./AdminableUpgradeable.sol";

abstract contract RecruitLevelState is Initializable, IRecruitLevel, AdminableUpgradeable {

    // Config events
    event MaxLevelSet(uint16 maxLevel);
    event AscensionInfoSet(uint16 minimumLevelCadet, uint16 numEoSCadet, uint16 numPrismShardsCadet, uint16 minimumLevelApprentice, uint16 numEoSApprentice, uint16 numPrismShardsApprentice);
    event LevelUpInfoSet(uint16 levelCur, uint32 expToNextLevel);

    // Recruit changed events
    event RecruitXPChanged(uint256 indexed tokenId, uint16 levelCur, uint32 expCur);
    event RecruitTypeChanged(uint256 indexed tokenId, RecruitType recruitType);

    uint256 constant EOS_ID = 8;
    uint256 constant PRISM_SHARD_ID = 9;

    ILegionMetadataStore public legionMetadataStore;
    IConsumable public consumable;
    ILegion public legion;

    mapping(uint256 => RecruitInfo) public tokenIdToRecruitInfo;
    mapping(uint16 => LevelUpInfo) public levelCurToLevelUpInfo;
    uint16 public maxLevel;
    AscensionInfo public ascensionInfo;

    function __RecruitLevelState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
    }
}

struct RecruitInfo {
    // May be None if they have not ascended to one of the recruit types
    RecruitType recruitType;
    // Starts at 1.
    uint16 levelCur;
    // Starts at 0. Reset to 0 after every level. Not cumulative.
    uint32 expCur;
    uint200 emptySpace;
}

struct LevelUpInfo {
    uint32 expToNextLevel;
    uint224 emptySpace;
}

// Do not add data past the size of 1 uint256. This struct is not stored in a mapping, but directly in the beginning of the storage
// layout.
//
struct AscensionInfo {
    uint16 minimumLevelCadet;
    uint16 numEoSCadet;
    uint16 numPrismShardsCadet;
    uint16 minimumLevelApprentice;
    uint16 numEoSApprentice;
    uint16 numPrismShardsApprentice;
    uint160 emptySpace;
}
