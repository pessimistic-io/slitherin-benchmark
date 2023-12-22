//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StructuredLinkedList.sol";

struct Temple {
    Coordinate coordinate;
    address harvesterAddress;
    uint32 latestRoundIdEnterable;
    uint16 templeId;
}

struct MapTile {
    //56 TOTAL BITS.
    uint32 mapTileId;
    uint8 mapTileType;
    uint8 moves;
    bool north;
    bool east;
    bool south;
    bool west;
    // directions of roads on each MapTile
}

enum MoveType {
    ClaimMapTiles,
    PlaceMapTile,
    EnterTemple,
    ClaimTreasure,
    MoveLegionSquad,
    CreateLegionSquad,
    PlaceLegionSquad,
    RemoveLegionSquad,
    DissolveLegionSquad,
    BlowUpMapTile
}

struct Coordinate {
    uint8 x;
    uint8 y;
}

struct Move {
    MoveType moveTypeId;
    bytes moveData;
}

struct Cell {
    //56 BITS.
    MapTile mapTile;
    //2 BITS
    bool hasMapTile;
    //64 BITS
    uint64 legionSquadId;
    //2 BITS
    bool hasLegionSquad;
}

struct LegionSquadInfo {
    //160 bites
    address owner;
    //64 bits
    uint64 legionSquadId;
    //32 bits
    uint32 lastRoundEnteredTemple;
    //32 bits
    uint32 mostRecentRoundTreasureClaimed;
    //16 bits
    Coordinate coordinate;
    //8 bits
    uint16 targetTemple;
    //8 bits
    bool inTemple;
    //8 bits
    bool exists;
    //8 bits
    bool onBoard;
    //224 bits left over
    //x * 16 bits
    uint32[] legionIds;
    //arbitrary number of bits
    string legionSquadName;
}

struct UserData {
    mapping(uint256 => uint256) roundIdToEpochLastClaimedMapTiles;
    mapping(uint32 => Coordinate) mapTileIdToCoordinate;
    StructuredLinkedList.List mapTilesOnBoard;
    Cell[16][10] currentBoard;
    MapTile[] mapTilesInHand;
    uint64 mostRecentUnstakeTime;
    uint64 requestId;
    uint8 numberOfLegionSquadsOnBoard;
}

struct BoardTreasure {
    Coordinate coordinate;
    uint8 treasureTier;
    uint8 affinity;
    uint8 correspondingId;
    uint16 numClaimed;
    uint16 maxSupply;
}

struct StakingDetails {
    bool staked;
    address staker;
}

struct GameConfig {
    uint256 secondsInEpoch;
    uint256 numLegionsReachedTempleToAdvanceRound;
    uint256 maxMapTilesInHand;
    uint256 maxMapTilesOnBoard;
    uint256 maximumLegionSquadsOnBoard;
    uint256 maximumLegionsInSquad;
    uint64 legionUnstakeCooldown;
    uint256 minimumDistanceFromTempleForLegionSquad;
    uint256 EOSID;
    uint256 EOSAmount;
    uint256 prismShardID;
    uint256 prismShardAmount;
}

interface ICorruptionCryptsInternal {
    function withinDistanceOfTemple(Coordinate memory, uint16)
        external
        view
        returns (bool);

    function generateTemplePositions() external view returns (Temple[] memory);

    function updateHarvestersRecord() external;

    function decideMovabilityBasedOnTwoCoordinates(
        address,
        Coordinate memory,
        Coordinate memory
    ) external view returns (bool);

    function generateMapTiles(uint256, address)
        external
        view
        returns (MapTile[] memory);

    function calculateNumPendingMapTiles(address)
        external
        view
        returns (uint256);

    function currentEpoch() external view returns (uint256);

    function generateTempleCoordinate(uint256)
        external
        view
        returns (Coordinate memory);

    function generateBoardTreasure()
        external
        view
        returns (BoardTreasure memory);

    function getMapTileByIDAndUser(uint32, address)
        external
        view
        returns (MapTile memory, uint256);
}

