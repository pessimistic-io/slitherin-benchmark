//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasureTriadBoardGeneration.sol";

contract TreasureTriad is Initializable, TreasureTriadBoardGeneration {

    function initialize() external initializer {
        TreasureTriadBoardGeneration.__TreasureTriadBoardGeneration_init();
    }

    // _userMoves length has already been verified.
    function generateBoardAndPlayGame(
        uint256 _randomNumber,
        LegionClass _legionClass,
        UserMove[] calldata _userMoves)
    external
    view
    override
    returns(GameOutcome memory)
    {
        GridCell[3][3] memory _gameBoard = generateBoard(_randomNumber);

        return playGame(_gameBoard, _legionClass, _userMoves);
    }

    function playGame(
        GridCell[3][3] memory _gameBoard,
        LegionClass _legionClass,
        UserMove[] calldata _userMoves)
    public
    view
    returns(GameOutcome memory)
    {
        // Loop through moves and play the cards.
        for(uint256 i = 0; i < _userMoves.length; i++) {
            UserMove calldata _userMove = _userMoves[i];

            _placeAndFlipCards(_gameBoard, _legionClass, _userMove);
        }

        return _determineOutcome(_gameBoard);
    }

    function _determineOutcome(GridCell[3][3] memory _gameBoard) private view returns(GameOutcome memory) {
        GameOutcome memory _outcome;
        for(uint256 x = 0; x < 3; x++) {
            for(uint256 y = 0; y < 3; y++) {
                if(_gameBoard[y][x].isFlipped) {
                    _outcome.numberOfFlippedCards++;
                }
                if(_gameBoard[y][x].isCorrupted) {
                    // Either they didn't place a card on the corrupted cell.
                    // Or the corrupted cell was a nature cell and they did not flip it.
                    if(_gameBoard[y][x].playerType == PlayerType.NONE) {
                        _outcome.numberOfCorruptedCardsLeft++;
                    } else if(_gameBoard[y][x].playerType == PlayerType.NATURE && !_gameBoard[y][x].isFlipped) {
                        _outcome.numberOfCorruptedCardsLeft++;
                    }
                }
            }
        }

        _outcome.playerWon = _outcome.numberOfFlippedCards >= numberOfFlippedCardsToWin;

        return _outcome;
    }

    function _placeAndFlipCards(GridCell[3][3] memory _gameBoard, LegionClass _legionClass, UserMove calldata _userMove) private view {
        require(_userMove.x < 3 && _userMove.y < 3, "TreasureTriad: Bad move indices");

        GridCell memory _playerCell = _gameBoard[_userMove.y][_userMove.x];

        require(_playerCell.playerType == PlayerType.NONE, "TreasureTriad: Cell is occupied");

        _playerCell.playerType = PlayerType.USER;
        _playerCell.treasureId = _userMove.treasureId;

        uint8 _playerCardBoost = _getCardBoost(_playerCell, _legionClass);

        if(_userMove.x > 0) { // West
            GridCell memory _cellToWest = _gameBoard[_userMove.y][_userMove.x - 1];
            if(_cellToWest.playerType == PlayerType.NATURE && !_cellToWest.isFlipped) {
                uint8 _natureCardBoost = _getCardBoost(_cellToWest, _legionClass);
                uint8 _natureCardValue = treasureIdToCardInfo[_cellToWest.treasureId].east + _natureCardBoost;
                uint8 _playerCardValue = treasureIdToCardInfo[_playerCell.treasureId].west + _playerCardBoost;
                if(_playerCardValue > _natureCardValue) {
                    _cellToWest.isFlipped = true;
                }
            }
        }
        if(_userMove.x < 2) { // East
            GridCell memory _cellToEast = _gameBoard[_userMove.y][_userMove.x + 1];
            if(_cellToEast.playerType == PlayerType.NATURE && !_cellToEast.isFlipped) {
                uint8 _natureCardBoost = _getCardBoost(_cellToEast, _legionClass);
                uint8 _natureCardValue = treasureIdToCardInfo[_cellToEast.treasureId].west + _natureCardBoost;
                uint8 _playerCardValue = treasureIdToCardInfo[_playerCell.treasureId].east + _playerCardBoost;
                if(_playerCardValue > _natureCardValue) {
                    _cellToEast.isFlipped = true;
                }
            }
        }
        if(_userMove.y > 0) { // North
            GridCell memory _cellToNorth = _gameBoard[_userMove.y - 1][_userMove.x];
            if(_cellToNorth.playerType == PlayerType.NATURE && !_cellToNorth.isFlipped) {
                uint8 _natureCardBoost = _getCardBoost(_cellToNorth, _legionClass);
                uint8 _natureCardValue = treasureIdToCardInfo[_cellToNorth.treasureId].south + _natureCardBoost;
                uint8 _playerCardValue = treasureIdToCardInfo[_playerCell.treasureId].north + _playerCardBoost;
                if(_playerCardValue > _natureCardValue) {
                    _cellToNorth.isFlipped = true;
                }
            }
        }
        if(_userMove.y < 2) { // South
            GridCell memory _cellToSouth = _gameBoard[_userMove.y + 1][_userMove.x];
            if(_cellToSouth.playerType == PlayerType.NATURE && !_cellToSouth.isFlipped) {
                uint8 _natureCardBoost = _getCardBoost(_cellToSouth, _legionClass);
                uint8 _natureCardValue = treasureIdToCardInfo[_cellToSouth.treasureId].north + _natureCardBoost;
                uint8 _playerCardValue = treasureIdToCardInfo[_playerCell.treasureId].south + _playerCardBoost;
                if(_playerCardValue > _natureCardValue) {
                    _cellToSouth.isFlipped = true;
                }
            }
        }
    }

    function _getCardBoost(GridCell memory _gridCell, LegionClass _legionClass) private view returns(uint8) {
        uint8 _boost;

        // No treasure placed or no affinity on cell.
        if(_gridCell.playerType == PlayerType.NONE || !_gridCell.hasAffinity) {
            return _boost;
        }

        if(_gridCell.playerType == PlayerType.USER
            && classToTreasureCategoryToHasAffinity[_legionClass][_gridCell.affinity])
        {
             _boost++;
        }

        if(_gridCell.affinity == affinityForTreasure(_gridCell.treasureId)) {
            _boost++;
        }

        return _boost;
    }
}
