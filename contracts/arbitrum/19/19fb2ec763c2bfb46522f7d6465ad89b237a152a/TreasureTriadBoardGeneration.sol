//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasureTriadSettings.sol";
import "./ILegionQuestingInfo.sol";

abstract contract TreasureTriadBoardGeneration is Initializable, TreasureTriadSettings {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __TreasureTriadBoardGeneration_init() internal initializer {
        TreasureTriadSettings.__TreasureTriadSettings_init();
    }

    function generateGameBoardForLegion(
        uint256 _legionId)
    public
    view
    returns(GridCell[3][3] memory)
    {
        ILegionQuestingInfo _legionQuestingInfo = ILegionQuestingInfo(address(advancedQuesting));

        uint256 _requestId = _legionQuestingInfo.requestIdForLegion(_legionId);
        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);
        uint8 _additionalCorruptedCells = _legionQuestingInfo.additionalCorruptedCellsForLegion(_legionId);

        return generateBoard(_randomNumber, _additionalCorruptedCells);
    }

    function generateGameBoardForRequest(
        uint256 _requestId)
    external
    view
    returns(GridCell[3][3] memory)
    {
        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        return generateBoard(_randomNumber, 0);
    }

    function generateBoard(uint256 _randomNumber, uint8 _additionalCorruptedCells) public view returns(GridCell[3][3] memory) {
        // Scramble the random with a constant number to get something fresh. The original random number may have been used.
        // Each random "thing" will use 8 bits, so we have 32 randoms within this number.
        _randomNumber = uint256(keccak256(abi.encode(_randomNumber,
            87286653073518694003612111662158573257766609697701829039857854141943741550340)));

        GridCell[3][3] memory _gameBoard;

        // Uses 72 bits of the random number
        _randomNumber = _placeNatureCards(_gameBoard, _randomNumber);

        // Uses 32 bits of the random number
        _randomNumber = _placeAffinities(_gameBoard, _randomNumber);

        // Uses 8-24 bits of the random number.
        _placeCorruptCells(_gameBoard, _randomNumber, _additionalCorruptedCells);

        return _gameBoard;
    }

    function _placeCorruptCells(
        GridCell[3][3] memory _gameBoard,
        uint256 _randomNumber,
        uint8 _additionalCorruptedCells)
    private
    pure
    {
        // The options for number of corrupted cells are 0, 1, 2.
        uint8 _numberOfCorruptedCells = uint8(_randomNumber % MAX_NUMBER_OF_CORRUPTED_CELLS + 1) + _additionalCorruptedCells;
        if(_numberOfCorruptedCells == 0) {
            return;
        }

        _randomNumber >>= 8;

        uint8[2][] memory _corruptedCellCoordinates = _pickRandomUniqueCoordinates(_numberOfCorruptedCells, _randomNumber);

        for(uint256 i = 0; i < _numberOfCorruptedCells; i++) {
            _gameBoard[_corruptedCellCoordinates[i][0]][_corruptedCellCoordinates[i][1]].isCorrupted = true;
        }
    }

    function _placeAffinities(
        GridCell[3][3] memory _gameBoard,
        uint256 _randomNumber)
    private
    pure
    returns(uint256)
    {
        uint8[2][] memory _affinityCellCoordinates = _pickRandomUniqueCoordinates(NUMBER_OF_CELLS_WITH_AFFINITY, _randomNumber);

        _randomNumber >>= (8 * NUMBER_OF_CELLS_WITH_AFFINITY);

        for(uint256 i = 0; i < NUMBER_OF_CELLS_WITH_AFFINITY; i++) {
            // Pick affinity type. Six affinities in total.
            TreasureCategory _affinity = TreasureCategory(_randomNumber % 6);

            _randomNumber >>= 8;

            _gameBoard[_affinityCellCoordinates[i][0]][_affinityCellCoordinates[i][1]].hasAffinity = true;
            _gameBoard[_affinityCellCoordinates[i][0]][_affinityCellCoordinates[i][1]].affinity = _affinity;
        }

        return _randomNumber;
    }

    function _placeNatureCards(
        GridCell[3][3] memory _gameBoard,
        uint256 _randomNumber)
    private
    view
    returns(uint256)
    {
        uint8[2][] memory _contractTreasureCoordinates = _pickRandomUniqueCoordinates(NUMBER_OF_CONTRACT_CARDS, _randomNumber);

        _randomNumber >>= (8 * NUMBER_OF_CONTRACT_CARDS);

        for(uint256 i = 0; i < NUMBER_OF_CONTRACT_CARDS; i++) {
            // Pick tier
            uint256 _tierResult = _randomNumber % 256;
            _randomNumber >>= 8;

            uint256 _topRange = 0;

            uint8 _tier;

            for(uint256 j = 0; j < 5; j++) {
                _topRange += baseTreasureRarityPerTier[j];

                if(_tierResult < _topRange) {
                    _tier = uint8(j + 1);
                    break;
                }
            }

            uint256 _treasureId = treasureMetadataStore.getAnyRandomTreasureForTier(_tier, _randomNumber);

            _randomNumber >>= 8;

            _gameBoard[_contractTreasureCoordinates[i][0]][_contractTreasureCoordinates[i][1]].treasureId = _treasureId;
            _gameBoard[_contractTreasureCoordinates[i][0]][_contractTreasureCoordinates[i][1]].playerType = PlayerType.NATURE;
        }

        return _randomNumber;
    }

    // Need to adjust random number after calling this function.
    // Adjust be 8 * _amount bits.
    function _pickRandomUniqueCoordinates(
        uint8 _amount,
        uint256 _randomNumber)
    private
    pure
    returns(uint8[2][] memory)
    {
        uint8[2][9] memory _gridCells = [
            [0,0],
            [0,1],
            [0,2],
            [1,0],
            [1,1],
            [1,2],
            [2,0],
            [2,1],
            [2,2]
        ];

        uint8 _numCells = 9;

        uint8[2][] memory _pickedCoordinates = new uint8[2][](_amount);

        for(uint256 i = 0; i < _amount; i++) {
            uint256 _cell = _randomNumber % _numCells;
            _pickedCoordinates[i] = _gridCells[_cell];
            _randomNumber >>= 8;
            _numCells--;
            if(_cell != _numCells) {
                _gridCells[_cell] = _gridCells[_numCells];
            }
        }

        return _pickedCoordinates;
    }

}
