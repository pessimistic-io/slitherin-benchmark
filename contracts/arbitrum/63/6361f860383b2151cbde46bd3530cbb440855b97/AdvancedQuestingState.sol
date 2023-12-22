//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./IRandomizer.sol";
import "./IAdvancedQuesting.sol";
import "./AdminableUpgradeable.sol";
import "./IQuesting.sol";
import "./ILegion.sol";
import "./ILegionMetadataStore.sol";
import "./ITreasure.sol";
import "./IConsumable.sol";
import "./ITreasureMetadataStore.sol";
import "./ITreasureTriad.sol";
import "./ITreasureFragment.sol";

abstract contract AdvancedQuestingState is Initializable, IAdvancedQuesting, AdminableUpgradeable, ERC721HolderUpgradeable, ERC1155HolderUpgradeable {

    event AdvancedQuestStarted(address _owner, uint256 _requestId, StartQuestParams _startQuestParams);
    event AdvancedQuestContinued(address _owner, uint256 _legionId, uint256 _requestId, uint8 _toPart);
    event TreasureTriadPlayed(address _owner, uint256 _legionId, bool _playerWon, uint8 _numberOfCardsFlipped, uint8 _numberOfCorruptedCardsRemaining);
    event AdvancedQuestEnded(address _owner, uint256 _legionId, AdvancedQuestReward[] _rewards);

    // Used for event. Free to change
    struct AdvancedQuestReward {
        uint256 consumableId;
        uint256 consumableAmount;
        uint256 treasureFragmentId; // Assumed to be 1.
        uint256 treasureId; // Assumed to be 1.
    }

    IRandomizer public randomizer;
    IQuesting public questing;
    ILegion public legion;
    ILegionMetadataStore public legionMetadataStore;
    ITreasure public treasure;
    IConsumable public consumable;
    ITreasureMetadataStore public treasureMetadataStore;
    ITreasureTriad public treasureTriad;
    ITreasureFragment public treasureFragment;

    // The length of stasis per corrupted card.
    uint256 public stasisLengthForCorruptedCard;

    // The name of the zone to all of
    mapping(string => ZoneInfo) public zoneNameToInfo;

    // For a given generation, returns if they can experience stasis.
    mapping(LegionGeneration => bool) generationToCanHaveStasis;

    // The highest constellation rank for the given zone to how much the chance of stasis is reduced.
    // The value that is stored is out of 256, as is the probability calculation.
    mapping(uint8 => uint8) maxConstellationRankToReductionInStasis;

    mapping(uint256 => LegionQuestingInfo) internal legionIdToLegionQuestingInfo;

    function __AdvancedQuestingState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        stasisLengthForCorruptedCard = 1 days;

        generationToCanHaveStasis[LegionGeneration.GENESIS] = false;
        generationToCanHaveStasis[LegionGeneration.AUXILIARY] = true;

        maxConstellationRankToReductionInStasis[1] = 10;
        maxConstellationRankToReductionInStasis[2] = 15;
        maxConstellationRankToReductionInStasis[3] = 20;
        maxConstellationRankToReductionInStasis[4] = 23;
        maxConstellationRankToReductionInStasis[5] = 38;
        maxConstellationRankToReductionInStasis[6] = 51;
        maxConstellationRankToReductionInStasis[7] = 64;
    }
}

struct LegionQuestingInfo {
    // Will be 0 if not on a quest.
    // The time that the legion started the CURRENT part.
    uint256 startTime;
    // The current random request for the legion.
    // There may be multiple requests through the zone parts depending
    // on if they auto-advanced or not.
    uint256 requestId;
    // The outcome of treasure triad for the part the user ends on (advanceToPart).
    LegionTriadOutcome triadOutcome;
    // The ids of the treasure that was staked along with this legion.
    // May be empty. If empty, user cannot play treasure triad.
    EnumerableSetUpgradeable.UintSet treasureIds;
    mapping(uint256 => uint256) treasureIdToAmount;
    // The zone they are currently at.
    string zoneName;
    // The owner of this questing. This value only should be trusted if startTime > 0 and the legion is staked here.
    address owner;
    // Indicates how far the legion wants to go automatically.
    uint8 advanceToPart;
    // Which part the legion is currently at. May be 0 if they have not made it to part 1.
    uint8 currentPart;
}

struct LegionTriadOutcome {
    // If 0, triad has not been played for current part.
    uint256 timeTriadWasPlayed;
    // Indicates the number of corrupted cards that were left for the current part the legion is on.
    uint8 corruptedCellsRemainingForCurrentPart;
    // Number of cards flipped
    uint8 cardsFlipped;
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
