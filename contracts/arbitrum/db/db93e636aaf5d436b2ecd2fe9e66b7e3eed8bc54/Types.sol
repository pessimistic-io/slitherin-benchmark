// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint256 constant RESOLUTION = 10000;
uint256 constant PAYOUT_AMPLIFIER = 10 ** 24;

library Types {
    struct Bet {
        uint256 globalBetId;
        uint256 playerBetId;
        uint256 gameId;
        uint256 rolls;
        uint256 betNum;
        uint256 stake;
        uint256 payout;
        bool complete;
        uint256 opened;
        uint256 closed;
        uint256[50] data;
        address player;
    }

    struct Game {
        uint256 id;
        bool live;
        uint256 edge;
        uint256 date;
        address impl;
        string name;
    }

    struct HouseGame {
        uint256 betCount;
        uint256[] betIds;
    }

    struct PlayerGame {
        uint256 betCount;
        uint256 wagers;
        uint256 profits;
        uint256 wins;
        uint256 losses;
    }

    struct Player {
        uint256 betCount;
        uint256[] betIds;

        uint256 wagers;
        uint256 profits;

        uint256 wins;
        uint256 losses;
    }

    struct Player2 {
        Player info;
        mapping (uint256 => PlayerGame) games;
    }
}

/*
pragma solidity ^0.8.0;

uint256 constant RESOLUTION = 10000;
uint256 constant PAYOUT_AMPLIFIER = 10 ** 24;

type BETCOUNT is uint32;
type GAMECOUNT is uint16;
type DATAVALUE is uint128;
type ROLLCOUNT is uint16;
type BETNUM is uint32;
type TOKENAMOUNT is uint128;
type TIMESTAMP is uint32;
type EDGEAMOUNT is uint16;

library Types {

    function add(BETCOUNT a, uint256 b) internal pure returns (BETCOUNT) {
        return BETCOUNT.wrap(uint32(uint256(BETCOUNT.unwrap(a)) + b));
    }

    function toUint256(BETCOUNT a) internal pure returns (uint256) {
        return uint256(BETCOUNT.unwrap(a));
    }

    function add(GAMECOUNT a, uint256 b) internal pure returns (GAMECOUNT) {
        return GAMECOUNT.wrap(uint16(uint256(GAMECOUNT.unwrap(a)) + b));
    }

    struct Bet {
        BETCOUNT globalBetId;
        BETCOUNT playerBetId;
        GAMECOUNT gameId;
        ROLLCOUNT rolls;
        BETNUM betNum;
        TOKENAMOUNT stake;
        TOKENAMOUNT payout;
        bool complete;
        TIMESTAMP opened;
        TIMESTAMP closed;
        DATAVALUE[50] data;
        address player;
    }

    struct Game {
        GAMECOUNT id;
        bool live;
        EDGEAMOUNT edge;
        TIMESTAMP date;
        address impl;
        string name;
    }

    struct HouseGame {
        BETCOUNT betCount;
        BETCOUNT[] betIds;
    }

    struct PlayerGame {
        BETCOUNT betCount;
        TOKENAMOUNT wagers;
        TOKENAMOUNT profits;
        BETCOUNT wins;
        BETCOUNT losses;
    }

    struct Player {
        BETCOUNT betCount;
        BETCOUNT[] betIds;

        TOKENAMOUNT wagers;
        TOKENAMOUNT profits;

        BETCOUNT wins;
        BETCOUNT losses;

        mapping (GAMECOUNT => PlayerGame) games;
    }
}
*/
