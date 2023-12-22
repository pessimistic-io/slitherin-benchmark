//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IRandomizer.sol";
import "./AdminableUpgradeable.sol";
import "./IItemz.sol";
import "./IBugz.sol";
import "./IBadgez.sol";
import "./IWorld.sol";
import "./IAdventure.sol";

abstract contract AdventureState is Initializable, IAdventure, AdminableUpgradeable {

    // Used for the AdventureAddedEvent and as a function parameter
    struct InputItem {
        InputItemOption[] itemOptions;
    }

    struct InputItemOption {
        uint256 itemId;
        uint256 quantity;
        uint256 timeReduction;
        uint256 bugzReduction;
        int256 chanceOfSuccessChange;
    }

    event AdventureAdded(
        string _name,
        AdventureInfo _adventureInfo,
        InputItem[] _inputItems);

    event AdventureStarted(
        uint256 _tokenId,
        string _adventureName,
        uint256 _requestId,
        uint256 _startTime,
        uint256 _estimatedEndTime,
        uint256 _chanceOfSuccess,
        uint256[] _itemInputIds);

    event AdventureEnded(
        uint256 _tokenId,
        bool _succeeded,
        uint256 _rewardItemId,
        uint256 _rewardQuantity);

    IRandomizer public randomizer;
    IItemz public itemz;
    IBugz public bugz;
    IBadgez public badgez;
    IWorld public world;

    mapping(string => AdventureInfo) public nameToAdventureInfo;
    mapping(string => mapping(uint256 => InputInfo)) internal nameToInputIndexToInputInfo;

    mapping(uint256 => ToadAdventureInfo) internal tokenIdToToadAdventureInfo;
    // Keeps track of how many times a given toad has gone on an adventure.
    mapping(uint256 => mapping(string => uint256)) public tokenIdToNameToCount;

    mapping(address => mapping(uint256 => uint256)) public userToRewardIdToCount;

    uint256 public allLogTypesBadgeId;

    uint256 public log1Id;
    uint256 public log2Id;
    uint256 public log3Id;
    uint256 public log4Id;
    uint256 public log5Id;

    function __AdventureState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        allLogTypesBadgeId = 6;

        log1Id = 3;
        log2Id = 4;
        log3Id = 5;
        log4Id = 6;
        log5Id = 7;
    }
}

struct AdventureInfo {
    // The time that this adventure becomes active.
    uint256 adventureStart;
    // May be 0 if no planned stop date
    uint256 adventureStop;
    uint256 lengthForToad;
    uint256 bugzCost;
    // May be 0 if no max per toad
    uint256 maxTimesPerToad;
    // May be 0 if no max.
    uint256 maxTimesGlobally;
    // The current number of adventures that have been gone on.
    uint256 currentTimesGlobally;
    // The index of these inputs is used to find the different items that will
    // satisify the needs.
    bool[] isInputRequired;
    RewardOption[] rewardOptions;
    // The chance this adventure is a success. Out of 100,000.
    uint256 chanceSuccess;
    bool bugzReturnedOnFailure;
}

struct RewardOption {
    // The item ID of this reward;
    uint256 itemId;
    // The odds that this reward is picked out of 100,000
    int256 baseOdds;
    // The amount given out.
    uint256 rewardQuantity;
    // The id used as an input that will boost the odds, one way or another, for this reward option
    uint256 boostItemId;
    // The amount, positive or negative, that will change the baseOdds if the boostItemId was used as the input
    int256 boostAmount;
    // If greater than 0, this badge will be earned on hitting this reward.
    uint256 badgeId;
}

struct InputInfo {
    EnumerableSetUpgradeable.UintSet itemIds;
    mapping(uint256 => uint256) itemIdToQuantity;
    mapping(uint256 => uint256) itemIdToTimeReduction;
    mapping(uint256 => uint256) itemIdToBugzReduction;
    mapping(uint256 => int256) itemIdToChanceOfSuccessChange;
}

// Information about a toadz current adventure.
struct ToadAdventureInfo {
    string adventureName;
    // The start time of the adventure. Used to indicate if a toad is currently on an adventure. To save gas, other fields are not cleared.
    uint256 startTime;
    uint256 requestId;
    uint256 timeReduction;
    int256 chanceOfSuccessChange;
    // The number of bugz spent on this adventure. Only needed if the adventure fails
    // and the bugz are returned on failure.
    uint256 bugzSpent;

    EnumerableSetUpgradeable.UintSet inputItemIds;
    mapping(uint256 => uint256) inputIdToQuantity;
}
