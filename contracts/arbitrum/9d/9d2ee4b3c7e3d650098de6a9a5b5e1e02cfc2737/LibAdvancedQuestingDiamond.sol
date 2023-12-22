// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRandomizer.sol";
import "./IQuesting.sol";
import "./ILegion.sol";
import "./ILegionMetadataStore.sol";
import "./ITreasure.sol";
import "./IConsumable.sol";
import "./ITreasureMetadataStore.sol";
import "./ITreasureTriad.sol";
import "./ITreasureFragment.sol";
import "./IRecruitLevel.sol";
import "./IMasterOfInflation.sol";
import "./IPoolConfigProvider.sol";

// Remember to add the loupe functions from DiamondLoupeFacet to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

library LibAdvancedQuestingDiamond {
    struct AppStorage {
        IRandomizer randomizer;
        IQuesting questing;
        ILegion legion;
        ILegionMetadataStore legionMetadataStore;
        ITreasure treasure;
        IConsumable consumable;
        ITreasureMetadataStore treasureMetadataStore;
        ITreasureTriad treasureTriad;
        ITreasureFragment treasureFragment;

        // The length of stasis per corrupted card.
        uint256 stasisLengthForCorruptedCard;

        // The name of the zone to all of
        mapping(string => ZoneInfo) zoneNameToInfo;

        // For a given generation, returns if they can experience stasis.
        mapping(LegionGeneration => bool) generationToCanHaveStasis;

        // The highest constellation rank for the given zone to how much the chance of stasis is reduced.
        // The value that is stored is out of 256, as is the probability calculation.
        mapping(uint8 => uint8) maxConstellationRankToReductionInStasis;

        mapping(uint256 => LegionQuestingInfoV1) legionIdToLegionQuestingInfoV1;

        // The optimized version of the questing info struct.
        // Blunder on my part for not optimizing for gas better before launch.
        mapping(uint256 => LegionQuestingInfoV2) legionIdToLegionQuestingInfoV2;

        // The chance of a universal lock out of 100,000.
        uint256 chanceUniversalLock;

        // Putting this storage in ZoneInfo after the fact rekt it. A mapping will
        // be nice as if there are any out of bounds index, it will return 0.
        mapping(string => mapping(uint256 => mapping(uint256 => uint8[7]))) zoneNameToPartIndexToRewardIndexToQuestBoosts;

        mapping(uint8 => uint256) endingPartToQPGained;

        mapping(string => mapping(uint256 => RecruitPartInfo)) zoneNameToPartIndexToRecruitPartInfo;

        uint256 numQuesting;

        uint32 cadetRecruitFragmentBoost;

        IRecruitLevel recruitLevel;
        IMasterOfInflation masterOfInflation;

        // The time the fragment pools were first set. Used to start counting the
        // regular quests in progress. Do not want to consider quests that are happening mid-upgrade
        // for pool purposes.
        uint256 timePoolsFirstSet;
        mapping(uint8 => uint64) tierToPoolId;
        mapping(uint8 => uint64) tierToRecruitPoolId;

        uint256 numRecruitsQuesting;
    }

    struct LegionQuestingInfoV1 {
        uint256 startTime;
        uint256 requestId;
        LegionTriadOutcomeV1 triadOutcome;
        EnumerableSetUpgradeable.UintSet treasureIds;
        mapping(uint256 => uint256) treasureIdToAmount;
        string zoneName;
        address owner;
        uint8 advanceToPart;
        uint8 currentPart;
    }

    struct LegionTriadOutcomeV1 {
        // If 0, triad has not been played for current part.
        uint256 timeTriadWasPlayed;
        // Indicates the number of corrupted cards that were left for the current part the legion is on.
        uint8 corruptedCellsRemainingForCurrentPart;
        // Number of cards flipped
        uint8 cardsFlipped;
    }

    struct LegionQuestingInfoV2 {
        // Will be 0 if not on a quest.
        // The time that the legion started the CURRENT part.
        uint120 startTime;
        // If 0, triad has not been played for current part.
        uint120 timeTriadWasPlayed;
        // Indicates the number of corrupted cards that were left for the current part the legion is on.
        uint8 corruptedCellsRemainingForCurrentPart;
        // Number of cards flipped
        uint8 cardsFlipped;
        // The owner of this questing. This value only should be trusted if startTime > 0 and the legion is staked here.
        address owner;
        // The current random request for the legion.
        // There may be multiple requests through the zone parts depending
        // on if they auto-advanced or not.
        uint80 requestId;
        // Indicates how far the legion wants to go automatically.
        uint8 advanceToPart;
        // Which part the legion is currently at. May be 0 if they have not made it to part 1.
        uint8 currentPart;
        // The zone they are currently at.
        string zoneName;
        // All the treasures that may be staked. Stored this way for effeciency.
        Treasures treasures;
    }

    struct ZoneInfo {
        // The time this zone becomes active. If 0, zone does not exist.
        uint256 zoneStartTime;
        TreasureCategory categoryBoost1;
        TreasureCategory categoryBoost2;
        // The constellations that are considered for this zone.
        Constellation constellation1;
        Constellation constellation2;
        ZonePart[] parts;
    }

    struct ZonePart {
        // The length of time this zone takes to complete.
        uint256 zonePartLength;
        // The length of time added to the journey if the legion gets stasis.
        uint256 stasisLength;
        // The base rate of statis for the part of the zone. Out of 256.
        uint8 stasisBaseRate;
        // The quest level minimum required to proceed to this part of the zone.
        uint8 questingLevelRequirement;
        // DEPRECATED
        uint8 questingXpGained;
        // Indicates if the user needs to play treasure triad to complete this part of the journey.
        bool playTreasureTriad;
        // The different rewards given if the user ends their adventure on this part of the zone.
        ZoneReward[] rewards;
    }

    struct ZoneReward {
        // Out of 256 (255 max). How likely this reward group will be given to the user.
        uint8 baseRateRewardOdds;

        // Certain generations/rarities get a rate boost.
        // For example, only genesis legions are able to get full treasures from the zone.
        // And each rarity of legions (genesis and auxiliary) have a better chance for treasure pieces.
        uint8[][] generationToRarityToBoost;

        // Applies only when this zone part requires the user to play treasure triad.
        // This is the boost this reward gains per card that was flipped by the user.
        uint8 boostPerFlippedCard;

        // The different options for this reward.
        ZoneRewardOption[] rewardOptions;
    }

    struct ZoneRewardOption {
        // The consumable id associated with this reward option.
        // May be 0.
        uint256 consumableId;

        // The amount of the consumable given.
        uint256 consumableAmount;

        // ID associated to this treasure fragment. May be 0.
        uint256 treasureFragmentId;

        // The treasure tier if this option is to receive a full treasure.
        // May be 0 indicating no treasures
        uint8 treasureTier;

        // The category of treasure that will be minted for the given tier.
        TreasureCategory treasureCategory;

        // The odds out of 256 that this reward is picked from the options
        uint8 rewardOdds;
    }

    struct StartQuestParams {
        uint256 legionId;
        string zoneName;
        // What part to advance to. Should be between 1-maxParts.
        uint8 advanceToPart;
        // The treasures to stake with the legion.
        uint256[] treasureIds;
        uint256[] treasureAmounts;
    }

    // Pack the struct. 7 is the maximum number of treasures that can be staked.
    struct Treasures {
        uint8 numberOfTypesOfTreasures;
        uint16 treasure1Id;
        uint8 treasure1Amount;
        uint16 treasure2Id;
        uint8 treasure2Amount;
        uint16 treasure3Id;
        uint8 treasure3Amount;
        uint16 treasure4Id;
        uint8 treasure4Amount;
        uint16 treasure5Id;
        uint8 treasure5Amount;
        uint16 treasure6Id;
        uint8 treasure6Amount;
        uint16 treasure7Id;
        uint8 treasure7Amount;
    }

    struct RecruitPartInfo {
        uint8 numEoS;
        uint8 numShards;
        uint32 chanceUniversalLock;
        uint32 recruitXPGained;
        uint8 fragmentId;
        uint168 emptySpace;
    }
}
