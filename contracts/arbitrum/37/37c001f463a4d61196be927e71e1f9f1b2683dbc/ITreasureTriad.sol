// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITreasureMetadataStore.sol";
import "./ILegionMetadataStore.sol";

interface ITreasureTriad {
    function generateBoardAndPlayGame(
        uint256 _legionId,
        LegionClass _legionClass,
        UserMove[] calldata _userMoves)
    external
    view
    returns(GameOutcome memory);

}

enum PlayerType {
    NONE,
    NATURE,
    USER
}

// Represents the information contained in a single cell of the game grid.
struct GridCell {
    // The treasure played on this cell. May be 0 if PlayerType == NONE
    uint256 treasureId;

    // The type of player that has played on this cell.
    PlayerType playerType;

    // In the case that playerType == NATURE, if this is true, the player has flipped this card to their side.
    bool isFlipped;

    // Indicates if the cell is corrupted.
    // If the cell is empty, the player must place a card on it to make it uncorrupted.
    // If the cell has a contract/nature card, the player must flip the card to make it uncorrupted.
    bool isCorrupted;

    // Indicates if this cell has an affinity. If so, look at the affinity field.
    bool hasAffinity;

    // The affinity of this field. Only consider this field if hasAffinity is true.
    TreasureCategory affinity;
}

// Represents a move the end user will make.
struct UserMove {
    // The x coordinate of the location
    uint8 x;
    // The y coordinate of the location.
    uint8 y;
    // The treasure to place at this location.
    uint256 treasureId;
}

struct GameOutcome {
    uint8 numberOfFlippedCards;
    uint8 numberOfCorruptedCardsLeft;
    bool playerWon;
}
