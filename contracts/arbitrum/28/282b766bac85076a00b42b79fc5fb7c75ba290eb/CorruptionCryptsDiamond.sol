//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./FixedPointMathLib.sol";
import "./CorruptionCryptsDiamondState.sol";
import "./ICorruptionCryptsInternal.sol";

contract CorruptionCryptsDiamond is CorruptionCryptsDiamondState {
    modifier onlyValidLegionSquadAndLegionSquadOwner(
        address _user,
        uint64 _legionSquadId
    ) {
        require(
            legionSquadIdToLegionSquadInfo[_legionSquadId].owner == _user &&
                legionSquadIdToLegionSquadInfo[_legionSquadId].exists,
            "You don't own this legion squad!"
        );
        _;
    }

    function advanceRound() external onlyAdminOrOwner {
        _advanceRound();
    }

    function _advanceRound() private  {
        //Increment round
        currentRoundId++;

        //Request new global randomness.
        globalRequestId = randomizer.requestRandomNumber();
        emit GlobalRandomnessRequested(globalRequestId, currentRoundId);

        //Refresh the harvesters record.
        ICorruptionCryptsInternal(address(this)).updateHarvestersRecord();

        //Set num claimed to 0 for the board treasure.
        boardTreasure.numClaimed = 0;

        //Reset how many legions have reached the temple.
        numLegionsReachedTemple = 0;

        //Set round start time to now.
        roundStartTime = block.timestamp;
    }

    function claimMapTiles(address _user) internal {
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

        //How many epochs to reimburse (if any)
        uint256 epochsToReimburse = numPendingMapTiles - numToClaim;

        //Set lastClaimed epoch and subtract reimbursements.
        addressToUserData[_user].roundIdToEpochLastClaimedMapTiles[
            currentRoundId
        ] =
            ICorruptionCryptsInternal(address(this)).currentEpoch() -
            epochsToReimburse;

        //Generate an array randomly of map tiles to add.
        MapTile[] memory mapTilesToAdd = ICorruptionCryptsInternal(
            address(this)
        ).generateMapTiles(numToClaim, _user);

        for (uint256 i = 0; i < numToClaim; i++) {
            //Loop through array of map tiles.
            MapTile memory thisMapTile = mapTilesToAdd[i];

            //Push their map tile into their hand.
            addressToUserData[_user].mapTilesInHand.push(thisMapTile);
        }

        //Emit event from subgraph
        emit MapTilesClaimed(_user, mapTilesToAdd, currentRoundId);
    }

    function removeMapTileFromHandByIndexAndUser(uint256 _index, address _user)
        internal
    {
        //Load map tiles into memory
        MapTile[] storage mapTiles = addressToUserData[_user].mapTilesInHand;

        //Get the map tile that's at the end
        MapTile memory MapTileAtEnd = mapTiles[mapTiles.length - 1];


        //Overwrite the target index with the end map tile.
        addressToUserData[_user].mapTilesInHand[_index] = MapTileAtEnd;

        //Remove the final map tile
        addressToUserData[_user].mapTilesInHand.pop();

    }

    function removeMapTileFromBoard(address _user, uint32 _mapTileIdToRemove)
        internal
    {
        uint32 _removedMapTileId;
        //If no id specified, pop from back
        if (_mapTileIdToRemove == 0) {
            _removedMapTileId = uint32(
                StructuredLinkedList.popBack(
                    addressToUserData[_user].mapTilesOnBoard
                )
            );
        } else {
            _removedMapTileId = uint32(
                StructuredLinkedList.remove(
                    addressToUserData[_user].mapTilesOnBoard,
                    _mapTileIdToRemove
                )
            );
        }
        //Get the coordinates of the removed tile
        Coordinate memory coordinateOfRemovedMapTile = addressToUserData[_user]
            .mapTileIdToCoordinate[_removedMapTileId];

        addressToUserData[_user]
        .currentBoard[coordinateOfRemovedMapTile.x][
            coordinateOfRemovedMapTile.y
        ].hasMapTile = false;

        addressToUserData[_user]
        .currentBoard[coordinateOfRemovedMapTile.x][
            coordinateOfRemovedMapTile.y
        ].mapTile = MapTile(0, 0, 0, false, false, false, false);

        //If a legion squad is currently on this tile, revert.
        require(
            !addressToUserData[_user]
            .currentBoard[coordinateOfRemovedMapTile.x][
                coordinateOfRemovedMapTile.y
            ].hasLegionSquad,
            "Has legion squad!"
        );

        emit MapTileRemovedFromBoard(_user, _removedMapTileId, coordinateOfRemovedMapTile);
    }

    function placeMapTile(
        address _user,
        uint32 _mapTileId,
        Coordinate memory _coordinate
    ) internal {
        //Pull this cell into memory
        Cell memory thisCell = addressToUserData[_user].currentBoard[
            _coordinate.x
        ][_coordinate.y];

        //Require this cell has no map tile
        require(!thisCell.hasMapTile, "Already has map tile!");

        //Get this full map tile struct and index from storage.
        (
            MapTile memory thisMapTile,
            uint256 _index
        ) = ICorruptionCryptsInternal(address(this)).getMapTileByIDAndUser(
                _mapTileId,
                _user
            );


        emit MapTileRemovedFromHand(_user, uint32(_mapTileId), true);

        //Delete this map tile from their hand.
        removeMapTileFromHandByIndexAndUser(_index, _user);

        //Overwrite the previous maptile on this cell, and record it as having a map tile. (empty)
        thisCell.mapTile = thisMapTile;
        thisCell.hasMapTile = true;

        //Store this cell on the board with adjusted data.
        addressToUserData[_user].currentBoard[_coordinate.x][
            _coordinate.y
        ] = thisCell;

        //Store the coordinates on this map tile.
        addressToUserData[_user].mapTileIdToCoordinate[
            thisMapTile.mapTileId
        ] = _coordinate;

        //Push this map tile into the front of the list
        StructuredLinkedList.pushFront(
            addressToUserData[_user].mapTilesOnBoard,
            thisMapTile.mapTileId
        );

        //Remove oldest maptile on board IF there are now 11 maptiles placed
        if (
            StructuredLinkedList.sizeOf(
                addressToUserData[_user].mapTilesOnBoard
            ) > gameConfig.maxMapTilesOnBoard
        ) {
            removeMapTileFromBoard(_user, 0);
        }

        //Emit event from subgraph
        emit MapTilePlaced(_user, thisMapTile, _coordinate, currentRoundId);
    }

    function enterTemple(address _user, uint64 _legionSquadId)
        internal
        onlyValidLegionSquadAndLegionSquadOwner(_user, _legionSquadId)
    {
        //Pull this legion squad into memory.
        LegionSquadInfo
            memory _legionSquadInfo = legionSquadIdToLegionSquadInfo[
                _legionSquadId
            ];

        uint16 _targetTemple = _legionSquadInfo.targetTemple;

        Temple[] memory _temples = ICorruptionCryptsInternal(address(this))
            .generateTemplePositions();
        Temple memory _targetTempleData;

        for (uint256 i = 0; i < _temples.length; i++) {
            if (_temples[i].templeId == _targetTemple) {
                _targetTempleData = _temples[i];
                break;
            }
        }

        //Ensure they are on this temple.
        require(
            _targetTempleData.coordinate.x == _legionSquadInfo.coordinate.x &&
                _targetTempleData.coordinate.y == _legionSquadInfo.coordinate.y,
            "Legion squad not at temple!"
        );

        //Ensure this is the temple they targeted.
        require(
            _legionSquadInfo.targetTemple == _targetTemple,
            "This was not the temple you targeted!"
        );

        require(_legionSquadInfo.onBoard, "Legion squad not on board!.");

        require(!_legionSquadInfo.inTemple, "Legion squad already in temple.");

        require(
            templeIdToTemples[uint16(_targetTemple)].latestRoundIdEnterable ==
                currentRoundId,
            "Temple is not enterable!"
        );

        corruptionCryptsRewards.onLegionsArrivedAtHarvester(_targetTempleData.harvesterAddress, _legionSquadInfo.legionIds);

        //Record they entered a temple in this round
        legionSquadIdToLegionSquadInfo[_legionSquadId]
            .lastRoundEnteredTemple = uint32(currentRoundId);

        //Record them as being in a temple.
        legionSquadIdToLegionSquadInfo[_legionSquadId].inTemple = true;

        //add this many legions as finished
        numLegionsReachedTemple += _legionSquadInfo.legionIds.length;


        emit TempleEntered(
            _user,
            _legionSquadId,
            _targetTemple,
            currentRoundId
        );

        if (
            numLegionsReachedTemple >=
            gameConfig.numLegionsReachedTempleToAdvanceRound
        ) _advanceRound();
    }

    function moveLegionSquad(
        address _user,
        uint64 _legionSquadId,
        uint32 _mapTileIdToBurn,
        Coordinate[] memory _coordinates
    ) internal onlyValidLegionSquadAndLegionSquadOwner(_user, _legionSquadId) {
        //This reverts if they do not have the tile.
        //Get this full map tile struct and index from storage.
        (
            MapTile memory thisMapTile,
            uint256 _index
        ) = ICorruptionCryptsInternal(address(this)).getMapTileByIDAndUser(
                _mapTileIdToBurn,
                _user
            );

        require(
            legionSquadIdToLegionSquadInfo[_legionSquadId].onBoard,
            "Legion squad not on board!."
        );

        Coordinate memory _startingCoordinate = legionSquadIdToLegionSquadInfo[
            _legionSquadId
        ].coordinate;

        Cell memory _finalCell = addressToUserData[_user].currentBoard[
            _coordinates[_coordinates.length - 1].x
        ][_coordinates[_coordinates.length - 1].y];

        Cell memory _startingCell = addressToUserData[_user].currentBoard[
            _startingCoordinate.x
        ][_startingCoordinate.y];


        emit MapTileRemovedFromHand(_user, _mapTileIdToBurn, false);

        removeMapTileFromHandByIndexAndUser(_index, _user);

        //If they are in a temple, check if they entered in this round or a previous round
        if (legionSquadIdToLegionSquadInfo[_legionSquadId].inTemple) {
            //If they entered this round, revert.
            require(
                currentRoundId != 
                    legionSquadIdToLegionSquadInfo[_legionSquadId]
                        .lastRoundEnteredTemple,
                "Have already entered a temple this round!"
            );

            //If it was a different round, set them as not being in a temple.
            legionSquadIdToLegionSquadInfo[_legionSquadId].inTemple = false;
        }

        //Require the moves on the maptile eq or gt coordinates length
        require(
            thisMapTile.moves >= _coordinates.length,
            "Not enough moves on this map tile!"
        );

        //Require they destination has no legion squad.
        require(
            !_finalCell.hasLegionSquad,
            "Target cell already has legion squad!"
        );

        //Require Legion squad on coordinate
        require(
            _startingCell.hasLegionSquad &&
                _startingCell.legionSquadId == _legionSquadId,
            "Legion squad not on this coordinate!"
        );

        //If they claimed this round, don't try and find out if they can.
        bool hasClaimedTreasure = (
            legionSquadIdToLegionSquadInfo[_legionSquadId]
                .mostRecentRoundTreasureClaimed == currentRoundId
                ? true
                : false
        );

        BoardTreasure memory _boardTreasure = ICorruptionCryptsInternal(
            address(this)
        ).generateBoardTreasure();

        for (uint256 i = 0; i < _coordinates.length; i++) {
            //Require i coordinate and i + 1 coordinate are legal.
            require(
                ICorruptionCryptsInternal(address(this))
                    .decideMovabilityBasedOnTwoCoordinates(
                        _user,
                         (i == 0 ? _startingCoordinate : _coordinates[i - 1]), _coordinates[i]
                    ),
                "MapTiles are not connected"
            );

            //If they haven't claimed treasure, and they are on a treasure, claim it with a bypass.
            if (
                !hasClaimedTreasure &&
                (_coordinates[i].x == _boardTreasure.coordinate.x &&
                    _coordinates[i].y == _boardTreasure.coordinate.y)
            ) {
                hasClaimedTreasure = true;
                //Claim this treasure, with bypass true.
                claimTreasure(_user, _legionSquadId, true);
            }
        }

        //Remove legion squad from starting cell
        _startingCell.hasLegionSquad = false;
        _startingCell.legionSquadId = 0;

        //Set cell data to adjusted data.
        addressToUserData[_user].currentBoard[_startingCoordinate.x][
                _startingCoordinate.y
            ] = _startingCell;

        _finalCell.hasLegionSquad = true;
        _finalCell.legionSquadId = _legionSquadId;

        //Set this final cell as to having a legion squad
        addressToUserData[_user].currentBoard[
            _coordinates[_coordinates.length - 1].x
        ][_coordinates[_coordinates.length - 1].y] = _finalCell;

        //Set this legion squads location data to the final coordinate they submitted.
        legionSquadIdToLegionSquadInfo[_legionSquadId]
            .coordinate = _coordinates[_coordinates.length - 1];

        emit LegionSquadMoved(
            _user,
            _legionSquadId,
            _coordinates[_coordinates.length - 1]
        );
    }

    function claimTreasure(
        address _user,
        uint64 _legionSquadId,
        bool _bypassCoordinateCheck
    ) internal onlyValidLegionSquadAndLegionSquadOwner(_user, _legionSquadId) {
        BoardTreasure memory _boardTreasure = ICorruptionCryptsInternal(
            address(this)
        ).generateBoardTreasure();

        LegionSquadInfo
            memory _legionSquadInfo = legionSquadIdToLegionSquadInfo[
                _legionSquadId
            ];

        require(_legionSquadInfo.onBoard, "Legion squad not on board!.");

        //If this call is coming from a place that has already ensured they are allowed to claim it, bypass the coordinate check.
        //Not publically callable, so no chance of exploitation thru passing true when not allowed.
        if (!_bypassCoordinateCheck) {
            //Pull coordinate into memory.
            Coordinate memory _currentCoordinate = _legionSquadInfo.coordinate;

            //Require they are on the treasure.
            require(
                _currentCoordinate.x == _boardTreasure.coordinate.x &&
                    _currentCoordinate.y == _boardTreasure.coordinate.y,
                "You aren't on the treasure!"
            );
        }

        //Require max treasures haven't been claimed
        if(_boardTreasure.numClaimed >= _boardTreasure.maxSupply) return;

        //Require they haven't claimed a fragment this round
        if(_legionSquadInfo.mostRecentRoundTreasureClaimed >= currentRoundId) return;

        //Record that they claimed this round
        legionSquadIdToLegionSquadInfo[_legionSquadId]
            .mostRecentRoundTreasureClaimed = uint32(currentRoundId);

        //increment num claimed.
        boardTreasure.numClaimed += uint16(_legionSquadInfo.legionIds.length);

        //Mint them as many fragments as they have legions
        treasureFragment.mint(_user, _boardTreasure.correspondingId, _legionSquadInfo.legionIds.length);

        //emit event
        emit TreasureClaimed(
            _user,
            _legionSquadId,
            _legionSquadInfo.legionIds.length,
            _boardTreasure,
            currentRoundId
        );
    }

    function createLegionSquad(
        address _user,
        uint32[] memory _legionIds,
        uint256 _targetTemple,
        string memory _legionSquadName
    ) internal {
         //Ensure they do not have staking cooldown
        require(
            block.timestamp >= (addressToUserData[_user].mostRecentUnstakeTime + gameConfig.legionUnstakeCooldown),
            "cooldown hasn't ended!"
        );
        
        require(
            _legionIds.length <= gameConfig.maximumLegionsInSquad,
            "Exceeds maximum legions in squad."
        );

        //Ensure they have less than X
        require(
            addressToUserData[_user].numberOfLegionSquadsOnBoard <
                gameConfig.maximumLegionSquadsOnBoard,
            "Already have maximum squads on field"
        );

        //Increment how many they have.
        addressToUserData[_user].numberOfLegionSquadsOnBoard++;

        //Ensure they own all the legions
        //Mark as staked
        for (uint256 i = 0; i < _legionIds.length; i++) {
            //Ensure they're not a recruit
            require(
                legionMetadataStore
                    .metadataForLegion(_legionIds[i])
                    .legionGeneration != LegionGeneration.RECRUIT,
                "Legion cannot be a recruit!"
            );

            //Transfer it to the staking contract
            legionContract.adminSafeTransferFrom(
                _user,
                address(this),
                _legionIds[i]
            );
        }

        //Ensure temple is currently enterable
        require(
            templeIdToTemples[uint16(_targetTemple)].latestRoundIdEnterable ==
                currentRoundId,
            "Temple is not active!"
        );

        uint64 thisLegionSquadId = legionSquadCurrentId;
        legionSquadCurrentId++;

        legionSquadIdToLegionSquadInfo[thisLegionSquadId] = LegionSquadInfo(
            //Owner
            msg.sender,
            //This id
            thisLegionSquadId,
            //Last round entered temple
            0,
            //Most recent round treasure claimed
            0,
            //Coordinate
            Coordinate(0, 0),
            //Target temple
            uint16(_targetTemple),
            //In temple
            false,
            //Exists
            true,
            //On board
            false,
            //Legion Ids
            _legionIds,
            //Legion Squad Name
            _legionSquadName
        );

        //Increment legion squad current Id
        legionSquadCurrentId++;

        emit LegionSquadStaked(
            _user,
            thisLegionSquadId,
            _legionIds,
            uint16(_targetTemple),
            _legionSquadName
        );
    }

    function placeLegionSquad(
        address _user,
        uint64 _legionSquadId,
        Coordinate memory _coordinate
    ) internal onlyValidLegionSquadAndLegionSquadOwner(_user, _legionSquadId) {
        //Ensure they do not have staking cooldown
        require(
            block.timestamp >= (addressToUserData[_user].mostRecentUnstakeTime + gameConfig.legionUnstakeCooldown),
            "cooldown hasn't ended!"
        );

        //Require they are currently off board
        require(
            !legionSquadIdToLegionSquadInfo[_legionSquadId].onBoard,
            "Legion squad already on board!"
        );

        //Require they are placing it >x distance from a temple.
        require(
            !ICorruptionCryptsInternal(address(this)).withinDistanceOfTemple(
                _coordinate,
                legionSquadIdToLegionSquadInfo[_legionSquadId].targetTemple
            ),
            "Placement is too close to a temple!"
        );

        //Pull this cell into memory
        Cell memory thisCell = addressToUserData[_user].currentBoard[
            _coordinate.x
        ][_coordinate.y];

        //Ensure this cell does not have a legion squad
        require(!thisCell.hasLegionSquad, "Cell already has legion squad!");

        //Ensure map tiles exists here
        require(thisCell.hasMapTile, "This cell has no map tile");

        //Set cell to containing this legion squad id
        thisCell.legionSquadId = _legionSquadId;

        //Set cell to containing a legion squad
        thisCell.hasLegionSquad = true;

        //Store cell.
        addressToUserData[_user].currentBoard[_coordinate.x][
            _coordinate.y
        ] = thisCell;

        //Store them on this coordinate
        legionSquadIdToLegionSquadInfo[_legionSquadId].coordinate = _coordinate;

        //Set them as on the board.
        legionSquadIdToLegionSquadInfo[_legionSquadId].onBoard = true;

        emit LegionSquadMoved(_user, _legionSquadId, _coordinate);
    }

    function removeLegionSquad(address _user, uint64 _legionSquadId)
        internal
        onlyValidLegionSquadAndLegionSquadOwner(_user, _legionSquadId)
    {
        LegionSquadInfo
            memory _legionSquadInfo = legionSquadIdToLegionSquadInfo[
                _legionSquadId
            ];

        require(_legionSquadInfo.onBoard, "Legion squad not on board!.");

        //Set their cooldown to now plus cooldown time.
        addressToUserData[_user].mostRecentUnstakeTime = uint64(block.timestamp);

        //Remove it from its cell.
        addressToUserData[_user]
        .currentBoard[_legionSquadInfo.coordinate.x][
            _legionSquadInfo.coordinate.y
        ].hasLegionSquad = false;

        //Record legion squad as 0
        addressToUserData[_user]
        .currentBoard[_legionSquadInfo.coordinate.x][
            _legionSquadInfo.coordinate.y
        ].legionSquadId = 0;

        //Mark as off board
        legionSquadIdToLegionSquadInfo[_legionSquadId].onBoard = false;

        emit LegionSquadRemoved(_user, _legionSquadId);
    }

    function dissolveLegionSquad(address _user, uint64 _legionSquadId)
        internal
        onlyValidLegionSquadAndLegionSquadOwner(_user, _legionSquadId)
    {
        LegionSquadInfo
            memory _legionSquadInfo = legionSquadIdToLegionSquadInfo[
                _legionSquadId
            ];

        require(!_legionSquadInfo.onBoard, "Legion squad on board!.");

        //Mark it as not existing.
        legionSquadIdToLegionSquadInfo[_legionSquadId].exists = false;

        //Decrement one from the count of legion squads on the board.
        addressToUserData[_user].numberOfLegionSquadsOnBoard--;

        //Loop their legions and set as unstaked.
        for (uint256 i = 0; i < _legionSquadInfo.legionIds.length; i++) {
            //Transfer it from the staking contract
            legionContract.adminSafeTransferFrom(
                address(this),
                _user,
                _legionSquadInfo.legionIds[i]
            );
        }

        emit LegionSquadUnstaked(_user, _legionSquadId);
    }

    function blowUpMapTile(address _user, Coordinate memory _coordinate)
        internal
    {
        Cell memory _thisCell = addressToUserData[_user].currentBoard[
            _coordinate.x
        ][_coordinate.y];

        //Make sure there is a tile here
        require(_thisCell.hasMapTile, "This tile does not have a maptile!");
        //Make sure there is not a legion squad
        require(!_thisCell.hasLegionSquad, "This tile has a legion squad!");

        //Burn the essence of starlight.
        consumable.adminBurn(_user, gameConfig.EOSID, gameConfig.EOSAmount);
        //Burn the prism shards
        consumable.adminBurn(
            _user,
            gameConfig.prismShardID,
            gameConfig.prismShardAmount
        );

        removeMapTileFromBoard(_user, _thisCell.mapTile.mapTileId);
    }

    function takeTurn(Move[] calldata _moves) public {
        require(tx.origin == msg.sender, "Contracts cannot take turns!");
        
        bool claimedMapTiles;

        for (uint256 moveIndex = 0; moveIndex < _moves.length; moveIndex++) {
            Move calldata move = _moves[moveIndex];
            bytes calldata moveDataBytes = move.moveData;

            if (move.moveTypeId == MoveType.ClaimMapTiles) {
                //claim map tiles
                claimMapTiles(msg.sender);
                claimedMapTiles = true;
                continue;
            }

            if (move.moveTypeId == MoveType.PlaceMapTile) {
                //Place map tile

                (uint32 _mapTileId, Coordinate memory _coordinate) = abi.decode(
                    moveDataBytes,
                    (uint32, Coordinate)
                );

                placeMapTile(msg.sender, _mapTileId, _coordinate);
                continue;
            }

            if (move.moveTypeId == MoveType.EnterTemple) {
                //Enter temple

                uint64 _legionSquadId = abi.decode(moveDataBytes, (uint64));

                enterTemple(msg.sender, _legionSquadId);

                continue;
            }

            if (move.moveTypeId == MoveType.ClaimTreasure) {
                //Claim Treasure

                uint64 _legionSquadId = abi.decode(moveDataBytes, (uint64));

                //Claim this treasure, with bypass false.
                claimTreasure(msg.sender, _legionSquadId, false);

                continue;
            }

            if (move.moveTypeId == MoveType.MoveLegionSquad) {
                //Move legion squad

                (
                    uint64 _legionSquadId,
                    uint32 _mapTileId,
                    Coordinate[] memory _coordinates
                ) = abi.decode(moveDataBytes, (uint64, uint32, Coordinate[]));

                moveLegionSquad(
                    msg.sender,
                    _legionSquadId,
                    _mapTileId,
                    _coordinates
                );

                continue;
            }

            if (move.moveTypeId == MoveType.CreateLegionSquad) {
                //Create legion squad

                (
                    uint32[] memory _legionIds,
                    uint8 _targetTemple,
                    string memory _legionSquadName
                ) = abi.decode(moveDataBytes, (uint32[], uint8, string));

                createLegionSquad(
                    msg.sender,
                    _legionIds,
                    _targetTemple,
                    _legionSquadName
                );
                continue;
            }

            if (move.moveTypeId == MoveType.PlaceLegionSquad) {
                //Place legion squad

                (uint64 _legionSquadId, Coordinate memory _coordinate) = abi
                    .decode(moveDataBytes, (uint64, Coordinate));

                placeLegionSquad(msg.sender, _legionSquadId, _coordinate);
                continue;
            }

            if (move.moveTypeId == MoveType.RemoveLegionSquad) {
                //Remove legion squad

                uint64 _legionSquadId = abi.decode(moveDataBytes, (uint64));

                removeLegionSquad(msg.sender, _legionSquadId);

                continue;
            }

            if (move.moveTypeId == MoveType.DissolveLegionSquad) {
                //Dissolve legion squad

                uint64 _legionSquadId = abi.decode(moveDataBytes, (uint64));

                dissolveLegionSquad(msg.sender, _legionSquadId);

                continue;
            }

            if (move.moveTypeId == MoveType.BlowUpMapTile) {
                //BlowUpMapTile

                Coordinate memory _coordinate = abi.decode(
                    moveDataBytes,
                    (Coordinate)
                );

                blowUpMapTile(msg.sender, _coordinate);

                continue;
            }

            revert();
        }

        if (claimedMapTiles) {
            //If they claimed map tiles in this turn request a new random number.
            uint64 _requestId = uint64(randomizer.requestRandomNumber());

            //Store their request Id.
            addressToUserData[msg.sender].requestId = _requestId;
        }
    }
}

