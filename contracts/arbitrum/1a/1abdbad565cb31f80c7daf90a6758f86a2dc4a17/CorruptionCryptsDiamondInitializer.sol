//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DoubleEndedQueue.sol";
import "./FixedPointMathLib.sol";
import "./CorruptionCryptsDiamondState.sol";
import "./ICorruptionCryptsInternal.sol";

contract CorruptionCryptsDiamondInitializer is CorruptionCryptsDiamondState {
    function initialize(
        address _consumableAddress,
        address _randomizerAddress,
        address _legionContractAddress,
        address _harvestorFactoryAddress,
        address _treasureFragmentAddress,
        address _legionMetadataStoreAddress,
        address _corruptionCryptsRewardsAddress
    ) external initializer {
        AdminableUpgradeable.__Adminable_init();

        // proxy sets owner as 0x000000 address, manually call ownable here instead
        MapTiles.initMapTiles();

        //Initalize the board treasure
        boardTreasure = BoardTreasure(Coordinate(0, 0), 5, 0, 0, 0, 1000);

        /*
            SET VARS
        */

        gameConfig = GameConfig(
            //Seconds in epoch
            4 hours,
            //Legions to advance round
            1500,
            //max map tiles in hand
            6,
            //max map tiles on board
            10,
            //max legion squads on board
            1,
            //max legions in squad
            5,
            //legion unstake cooldown
            3 days,
            //minimum distance from temple for legion squads
            6,
            //EOSID
            8,
            //EOSAmount
            1,
            //prismShardId
            9,
            //prismShardAmount
            1
        );

        currentTempleId = 1;

        emit ConfigUpdated(gameConfig);

        //Set all the interface contracts
        consumable = IConsumable(_consumableAddress);
        randomizer = IRandomizer(_randomizerAddress);
        legionContract = ILegion(_legionContractAddress);
        harvesterFactory = IHarvesterFactory(_harvestorFactoryAddress);
        treasureFragment = ITreasureFragment(_treasureFragmentAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        corruptionCryptsRewards = ICorruptionCryptsRewards(
            _corruptionCryptsRewardsAddress
        );
    }

    function updateConfig(GameConfig memory _gameConfig)
        public
        onlyAdminOrOwner
    {
        gameConfig = _gameConfig;

        emit ConfigUpdated(_gameConfig);
    }

    function updateHarvestersRecord() external {
        require(
            msg.sender == address(this),
            "Call originated outside of diamond"
        );

        address[] memory _harvesters = harvesterFactory.getAllHarvesters();

        corruptionCryptsRewards.onNewRoundBegin(_harvesters);

        uint16[] memory _activeTemples = new uint16[](_harvesters.length);

        for (uint256 i = 0; i < _harvesters.length; i++) {
            address _thisHarvester = _harvesters[i];

            uint16 thisTempleId = harvesterAddressToTempleId[_thisHarvester];

            if (thisTempleId == 0) {
                //If there was no temple associated.
                thisTempleId = currentTempleId;

                //Store this address to the temple Id
                harvesterAddressToTempleId[_thisHarvester] = currentTempleId;

                //Store this address in the temple
                templeIdToTemples[thisTempleId]
                    .harvesterAddress = _thisHarvester;
                templeIdToTemples[thisTempleId].templeId = currentTempleId;

                emit TempleCreated(thisTempleId, _thisHarvester);

                //increment temple Id
                currentTempleId++;
            }

            templeIdToTemples[thisTempleId].latestRoundIdEnterable = uint32(
                currentRoundId
            );

            //Ensure this temple gets its coordinates refreshed.
            _activeTemples[i] = thisTempleId;
        }

        activeTemples = _activeTemples;
    }

    function startGame() external onlyAdminOrOwner {
        require(currentRoundId == 0, "Game already started");

        uint256 _startingRequestId = randomizer.requestRandomNumber();

        //Set the starting seed.
        globalStartingRequestId = _startingRequestId;

        //Set the current global request Id.
        globalRequestId = _startingRequestId;

        //Increment round
        currentRoundId = 1;

        //Refresh the harvesters record.
        ICorruptionCryptsInternal(address(this)).updateHarvestersRecord();

        //Set round start time to now.
        roundStartTime = block.timestamp;

        emit GlobalRandomnessRequested(globalRequestId, currentRoundId);
    }

    function hasGameStarted() external view returns (bool) {
        return globalStartingRequestId > 0;
    }

    function getPlayerMapTilesInHand(address _user)
        external
        view
        returns (MapTile[] memory)
    {
        return addressToUserData[_user].mapTilesInHand;
    }

    function addressToCurrentBoard(
        address _user,
        uint256 _cell,
        uint256 _row
    ) external view returns (Cell memory) {
        return addressToUserData[_user].currentBoard[_cell][_row];
    }

    function abs(int256 x) private pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function withinDistanceOfTemple(
        Coordinate memory _coordinate,
        uint16 _templeId
    ) external view returns (bool) {
        //Since temples cannot be on the same spot, you must generate all temple positions in order to
        //allow the temples to be sequentially generated, as opposed to just generating the position of one.
        Temple[] memory _temples = ICorruptionCryptsInternal(address(this))
            .generateTemplePositions();

        for (uint16 i = 0; i < _temples.length; i++) {
            if (_temples[i].templeId == _templeId) {
                //This is the targeted temple.

                int256 x1 = int256(int8(_coordinate.x));
                int256 y1 = int256(int8(_coordinate.y));

                int256 x2 = int256(int8(_temples[i].coordinate.x));
                int256 y2 = int256(int8(_temples[i].coordinate.y));

                //Using the taxicab formula, we can calculate the distance between two points in *moves*
                //|x1 − x2| + |y1 − y2|

                uint256 distance = uint256(abs(x1 - x2) + abs(y1 - y2));


                //If the distance is less than the minimum, return true.
                if (distance < gameConfig.minimumDistanceFromTempleForLegionSquad) return true;

                return false;
            } else {
                //If we haven't reached the target temple, continue.
                continue;
            }
        }

        //If the temple wasn't found, return false.
        return false;
    }

    function decideMovabilityBasedOnTwoCoordinates(
        address _user,
        Coordinate memory _startingCoordinate,
        Coordinate memory _endingCoordinate
    ) external view returns (bool) {
        Cell memory cell1 = addressToUserData[_user].currentBoard[
            _startingCoordinate.x
        ][_startingCoordinate.y];
        Cell memory cell2 = addressToUserData[_user].currentBoard[
            _endingCoordinate.x
        ][_endingCoordinate.y];

        require(cell2.hasMapTile, "Desired cell has no maptile.");

        MapTile memory startingMapTile = cell1.mapTile;
        MapTile memory endingMapTile = cell2.mapTile;

        if (_endingCoordinate.x < _startingCoordinate.x) {
            //Going left (x decreasing)
            require(
                _startingCoordinate.x - 1 == _endingCoordinate.x &&
                    _startingCoordinate.y == _endingCoordinate.y,
                "E cordinate movement invalid."
            );
            if (startingMapTile.west && endingMapTile.east) return true;
        }

        if (_endingCoordinate.x > _startingCoordinate.x) {
            //Going right (x increasing)
            require(
                _startingCoordinate.x + 1 == _endingCoordinate.x &&
                    _startingCoordinate.y == _endingCoordinate.y,
                "W coordinate movement invalid."
            );
            if (startingMapTile.east && endingMapTile.west) return true;
        }

        if (_endingCoordinate.y < _startingCoordinate.y) {
            //Going up (y decreasing)
            require(
                _startingCoordinate.x == _endingCoordinate.x &&
                    _startingCoordinate.y - 1 == _endingCoordinate.y,
                "N coordinate movement invalid."
            );
            if (startingMapTile.north && endingMapTile.south) return true;
        }

        if (_endingCoordinate.y > _startingCoordinate.y) {
            //Going down (y increasing)
            require(
                _startingCoordinate.x == _endingCoordinate.x &&
                    _startingCoordinate.y + 1 == _endingCoordinate.y,
                "S coordinate movement invalid."
            );
            if (startingMapTile.south && endingMapTile.north) return true;
        }

        return false;
    }

    function getLegionIdsByLegionSquadId(uint32 _legionSquadId)
        external
        view
        returns (uint32[] memory)
    {
        return legionSquadIdToLegionSquadInfo[_legionSquadId].legionIds;
    }

    function generateMapTiles(uint256 _quantity, address _user)
        external
        view
        returns (MapTile[] memory)
    {
        //Create in memory static array of length _quantity
        MapTile[] memory mapTilesReturn = new MapTile[](_quantity);

        uint256 localSeed;
        uint256 userRequestId = addressToUserData[_user].requestId;

        if (userRequestId == 0) {
            //Not seeded
            //Generate them Psuedo Random Number based on the very first seed, their address, and an arbitrary string.
            uint256 startingSeed = randomizer.revealRandomNumber(
                globalStartingRequestId
            );

            localSeed = uint256(
                keccak256(abi.encodePacked(startingSeed, _user, "mapTiles"))
            );
        } else {
            //Has been seeded
            //Get the seed
            //Might revert.
            localSeed = randomizer.revealRandomNumber(userRequestId);
        }

        for (uint256 i = 0; i < _quantity; i++) {
            //Generate a seed with the nonce and index of map tile.
            uint256 _seed = uint256(keccak256(abi.encodePacked(localSeed, i)));

            //Generate a random number from 0 - 35 and choose that mapTile.
            mapTilesReturn[i] = mapTiles[
                uint8(generateRandomNumber(0, 35, _seed))
            ];

            //Convert the seed into its uint32 counterpart, however modulo by uint32 ceiling so as to not always get 2^32
            //Overwrite the prevoius mapTileId with this new Id.
            mapTilesReturn[i].mapTileId = uint32(
                uint256(keccak256(abi.encodePacked(_seed, "1"))) % (2**32)
            );
        }

        return mapTilesReturn;
    }

    function currentEpoch() external view returns (uint256) {
        uint256 secondsSinceRoundStart = block.timestamp - roundStartTime;
        uint256 epochsSinceRoundStart = secondsSinceRoundStart /
            gameConfig.secondsInEpoch;
        return (epochsSinceRoundStart);
    }

    function calculateNumPendingMapTiles(address _user)
        external
        view
        returns (uint256)
    {
        //Pull the last epoch within the current round that this user claimed.
        uint256 lastEpochClaimed = addressToUserData[_user]
            .roundIdToEpochLastClaimedMapTiles[currentRoundId];

        //Calculate epochs passed by subtracting the last epoch claimed from the current epoch.
        uint256 epochsPassed = ICorruptionCryptsInternal(address(this))
            .currentEpoch() - lastEpochClaimed;

        //If the number of epochs passed is greater than the maximum map tiles you can hold.
        //Else return the epochs passed.
        uint256 numMapTilesToClaim = epochsPassed > gameConfig.maxMapTilesInHand
            ? gameConfig.maxMapTilesInHand
            : epochsPassed;

        return numMapTilesToClaim;
    }

    function getPlayerMapTilesPending(address _user)
        external
        view
        returns (MapTile[] memory)
    {
        //How many are in hand
        uint256 currentMapTilesInHand = addressToUserData[_user]
            .mapTilesInHand
            .length;

        //Maximum that can fit in current hand
        uint256 maxCanClaim = gameConfig.maxMapTilesInHand -
            currentMapTilesInHand;

        //How much total are pending
        uint256 numPendingMapTiles = ICorruptionCryptsInternal(address(this))
            .calculateNumPendingMapTiles(_user);

        //How many of the pending to claim (that can fit)
        uint256 numToClaim = numPendingMapTiles > maxCanClaim
            ? maxCanClaim
            : numPendingMapTiles;

        //Generate an array randomly of map tiles to add.
        MapTile[] memory pendingMapTiles = ICorruptionCryptsInternal(
            address(this)
        ).generateMapTiles(numToClaim, _user);

        return pendingMapTiles;
    }

    function generateTempleCoordinate(uint256 _index)
        public
        view
        returns (Coordinate memory)
    {
        uint256 _globalSeed = randomizer.revealRandomNumber(globalRequestId);

        //Generate a new seed from the global seed and the index of the current temple.
        uint256 localSeed = uint256(
            keccak256(abi.encodePacked(_globalSeed, _index))
        );

        //Decide what border it will sit on
        //For this randomness concat the local seed with 1
        uint256 border = generateRandomNumber(
            0,
            3,
            uint256(keccak256(abi.encodePacked(localSeed, uint256(1))))
        );

        //Now that you have a border, make new randomness with the number 2
        uint256 seed = uint256(
            keccak256(abi.encodePacked(localSeed, uint256(2)))
        );

        Coordinate memory thisCoordinate;

        if (border == 0)
            thisCoordinate = Coordinate(
                uint8(generateRandomNumber(0, 9, seed)),
                0
            );
        if (border == 1)
            thisCoordinate = Coordinate(
                9,
                uint8(generateRandomNumber(0, 15, seed))
            );
        if (border == 2)
            thisCoordinate = Coordinate(
                uint8(generateRandomNumber(0, 9, seed)),
                15
            );
        if (border == 3)
            thisCoordinate = Coordinate(
                0,
                uint8(generateRandomNumber(0, 15, seed))
            );

        return thisCoordinate;
    }

    function generateTemplePositions() external view returns (Temple[] memory) {
        uint256 _activeTemplesLength = activeTemples.length;

        Temple[] memory _temples = new Temple[](_activeTemplesLength);

        bool[16][10] memory usedCoordinates;
        uint256 _randomSeedOffset = 0;

        for (uint256 i = 0; i < _activeTemplesLength; i++) {
            _temples[i] = templeIdToTemples[activeTemples[i]];
            bool generated = false;
            while (!generated) {
                Coordinate memory thisCoordinate = generateTempleCoordinate(_randomSeedOffset);
                if (!usedCoordinates[thisCoordinate.x][thisCoordinate.y]) {
                    usedCoordinates[thisCoordinate.x][thisCoordinate.y] = true;
                    generated = true;
                    _temples[i].coordinate = thisCoordinate;
                }

                _randomSeedOffset++;
            }
        }

        return _temples;
    }

    function generateBoardTreasure()
        external
        view
        returns (BoardTreasure memory)
    {
        //Generate coordinate
        //Generate affinity
        //Num claimed and maxSupply persist.
        BoardTreasure memory _boardTreasure = boardTreasure;

        uint256 _globalSeed = randomizer.revealRandomNumber(globalRequestId);

        uint8 x = uint8(
            generateRandomNumber(
                0,
                9,
                uint256(keccak256(abi.encodePacked(_globalSeed, "treasuresx")))
            )
        );
        uint8 y = uint8(
            generateRandomNumber(
                0,
                15,
                uint256(keccak256(abi.encodePacked(_globalSeed, "treasuresy")))
            )
        );

        uint8 affinity = uint8(
            generateRandomNumber(
                0,
                2,
                uint256(
                    keccak256(abi.encodePacked(_globalSeed, "treasureaffinity"))
                )
            )
        );

        _boardTreasure.coordinate = Coordinate(x, y);
        _boardTreasure.affinity = affinity;
        _boardTreasure.correspondingId =
            (_boardTreasure.affinity * 5) +
            _boardTreasure.treasureTier;

        return _boardTreasure;
    }

    function getMapTileByIDAndUser(uint32 _mapTileId, address _user)
        external
        view
        returns (MapTile memory, uint256)
    {
        //Load hand into memory.
        MapTile[] storage _mapTiles = addressToUserData[_user].mapTilesInHand;
        for (uint256 i = 0; i < _mapTiles.length; i++) {
            //If this is the mapTile.
            if (_mapTiles[i].mapTileId == _mapTileId)
                //Return it, and its index.
                return (_mapTiles[i], i);
        }

        //Revert if you cannot find.
        revert("User doesn't possess this tile.");
    }

    function ownerOf(uint64 _legionSquadId) external view returns (address) {
        return legionSquadIdToLegionSquadInfo[_legionSquadId].owner;
    }

    function isLegionSquadActive(uint64 _legionSquadId)
        external
        view
        returns (bool)
    {
        return legionSquadIdToLegionSquadInfo[_legionSquadId].exists;
    }

    function getRoundStartTime() external view returns (uint256) {
        return roundStartTime;
    }

    function lastRoundEnteredTemple(uint64 _legionSquadId)
        external
        view
        returns (uint32)
    {
        return
            legionSquadIdToLegionSquadInfo[_legionSquadId]
                .lastRoundEnteredTemple;
    }

    function legionIdsForLegionSquad(uint64 _legionSquadId)
        external
        view
        returns (uint32[] memory)
    {
        return legionSquadIdToLegionSquadInfo[_legionSquadId].legionIds;
    }
}

