//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./StructuredLinkedList.sol";
import "./ICorruptionCryptsRewards.sol";
import "./ICryptsCharacterHandler.sol";
import "./ILegionMetadataStore.sol";
import "./IMasterOfInflation.sol";
import "./ITreasureFragment.sol";
import "./IHarvesterFactory.sol";
import "./IRandomizer.sol";
import "./AdminableUpgradeable.sol";
import "./ICorruptionCryptsInternal.sol";
import "./IConsumable.sol";
import "./ILegion.sol";
import "./MapTiles.sol";

abstract contract CorruptionCryptsDiamondState is
    Initializable,
    MapTiles,
    OwnableUpgradeable,
    AdminableUpgradeable
{
    using StructuredLinkedList for StructuredLinkedList.List;

    //External Contracts
    IConsumable public consumable;
    IRandomizer public randomizer;
    ILegion public legionContract;
    IHarvesterFactory public harvesterFactory;
    ITreasureFragment public treasureFragment;
    ILegionMetadataStore public legionMetadataStore;
    ICorruptionCryptsRewards public corruptionCryptsRewards;

    //Global Structs
    BoardTreasure boardTreasure;
    GameConfig public gameConfig;

    //Events
    event TreasureTierChanged(uint8 _newTreasureTier);

    event TreasureMaxSupplyChanged(uint16 _newTreasureMaxSupply);

    event MapTilesClaimed(address _user, MapTile[] _mapTiles, uint256 _roundId);

    event MapTilePlaced(
        address _user,
        MapTile _mapTile,
        Coordinate _coordinate,
        uint256 _roundId
    );

    event MapTileRemovedFromBoard(
        address _user,
        uint32 _mapTileId,
        Coordinate _coordinate
    );

    event MapTileRemovedFromHand(
        address _user,
        uint32 _mapTileId,
        bool _isBeingPlaced
    );

    event TempleEntered(
        address _user,
        uint64 _legionSquadId,
        uint16 _targetTemple,
        uint256 _roundId
    );

    event TempleCreated(uint16 thisTempleId, address _thisHarvester);

    event LegionSquadMoved(
        address _user,
        uint64 _legionSquadId,
        Coordinate _finalCoordinate
    );

    event LegionSquadStaked(
        address _user,
        uint64 _legionSquadId,
        CharacterInfo[] _characters,
        uint16 _targetTemple,
        string _legionSquadName
    );

    event LegionSquadRemoved(address _user, uint64 _legionSquadId);

    event LegionSquadUnstaked(address _user, uint64 _legionSquadId);

    //Emitted when requestGlobalRandomness() is called.
    event GlobalRandomnessRequested(uint256 _globalRequestId, uint256 _roundId);

    event TreasureClaimed(
        address _user,
        uint64 _legionSquadId,
        uint256 _treasureFragmentsEmitted,
        BoardTreasure _boardTreasure,
        uint256 _roundId
    );

    event ConfigUpdated(GameConfig _newConfig);

    event CharacterHandlerSet(address _collection, address _handler);

    event RoundAdvancePercentageUpdated(uint256 _percentageToReachForRoundAdvancement);

    //What round id this round is.
    uint256 public currentRoundId;

    //The timestamp that this round started at.
    uint256 roundStartTime;

    //How many legions have reached the temple this round.
    uint256 numLegionsReachedTemple;

    //Global seed (effects temples and treasures.).
    uint256 globalRequestId;

    //Record the first ever global seed (for future events like user first claiming map tiles.)
    uint256 globalStartingRequestId;

    //Current legion squad Id, increments up by one.
    uint64 legionSquadCurrentId;

    //Address to user data.
    mapping(address => UserData) addressToUserData;

    //Legion squad id to legion squad info.
    mapping(uint64 => LegionSquadInfo) legionSquadIdToLegionSquadInfo;

    //Record temple details.
    mapping(uint16 => Temple) templeIdToTemples;

    mapping(address => uint16) harvesterAddressToTempleId;

    uint16[] activeTemples;

    uint16 currentTempleId;

    mapping(address => address) public collectionToCryptsCharacterHandler;

    //Count total number of active legions
    uint256 public numActiveLegions;

    //% of legions currently staked to advance the round.
    uint256 public percentageToReachForRoundAdvancement;

    mapping(address => mapping(uint256 => uint32)) public characterToLastRoundClaimedTreasureFragment;

    //Master of inflation
    IMasterOfInflation public masterOfInflation;

    function generateRandomNumber(
        uint256 _min,
        uint256 _max,
        uint256 _seed
    ) internal pure returns (uint256) {
        return _min + (_seed % (_max + 1 - _min));
    }
}

