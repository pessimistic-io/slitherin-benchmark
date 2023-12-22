//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface Gameable {
    enum TierType {
        BORED,
        MUTANT,
        SOUL
    }

    struct NumberChosen {
        uint256 tokenID;
        uint256 number;
        uint256 balanceBeforeGame;
        uint256 createdAt;
    }

    struct UserGame {
        uint256 gameID;
        uint256 balanceBeforeGame;
        TierType category;
        bool isWinner;
    }

    struct Player {
        uint256 tokenID;
        string name;
        uint256 categoryPlayer;
        uint256 initialBalance;
        uint256 currentBalance;
        uint256 createdAt;
        uint256 number;
    }

    struct Game {
        uint256 id;
        uint256 winner;
        uint256 playersInGame;
        uint256 startedAt;
        uint256 endedAt;
        uint256 updatedAt;
        uint256 pool;
        TierType category;
    }

    struct Tier {
        TierType category;
        uint256 duration;
        uint256 amount;
        uint8 maxPlayer;
        uint256 createdAt;
        uint256 updatedAt;
        bool isActive;
    }

    function getGame(uint256 idGame) external returns (Game memory);

    function play(
        TierType category,
        uint256 tokenID,
        uint8 numberChosen
    ) external returns (uint256);

    function getGamesOf(uint256 tokenID) external returns (Game[] memory);

    function getGamesEndedBetweenIntervalOf(
        uint256 tokenID,
        uint256 startInterval,
        uint256 endInterval
    ) external view returns (UserGame[] memory);

    function getTier(TierType category) external view returns (Tier memory);
}

