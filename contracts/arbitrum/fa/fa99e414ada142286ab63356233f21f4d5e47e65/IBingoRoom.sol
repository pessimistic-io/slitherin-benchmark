// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBingoRoom {
    struct Participant {
        address user;
        uint256 cardId;
    }

    struct GameRound {
        uint32 round;
        uint8 number;
        uint32 timestamp;
        address player;
    }

    enum RecentGameFilter {
        // 0
        ALL,
        // 1
        LIVE,
        // 2
        FINISHED
    }

    event GameStarted(
        uint256 indexed gameId,
        address cardContract,
        address[] players
    );

    event GameParticipated(
        uint256 indexed gameId,
        address indexed player,
        uint256 indexed cardId,
        uint8 position
    );

    event NumberSelected(
        uint256 indexed gameId,
        uint32 round,
        address indexed player,
        uint8 number
    );

    event Bingo(
        uint256 indexed gameId,
        address indexed player,
        uint8[][] playerCardNumbers
    );

    event RewardChanged(
        address indexed newReward,
        address indexed oldReward
    );

    event GameHalted(
        uint256 indexed gameId,
        address indexed user,
        bool isOvertime
    );

    function gameCard() external view returns (address);

    function expectedLines() external view returns (uint8);

    function fee() external view returns (uint256 value, uint256 deno);

    function getGameInfo(
        uint256 gameId
    ) external view returns (
        uint32 startedAt,
        uint32 endedAt,
        address winner,
        Participant[] memory players,
        GameRound[] memory rounds,
        string memory status
    );

    function getCurrentRound(uint256 gameId) external view returns (
        uint32 round,
        address player,
        uint32 remain,
        string memory status
    );

    function getSelectedNumbers(
        uint256 gameId
    ) external view returns (uint8[] memory);

    function selectNumber(
        uint256 gameId,
        uint8 number
    ) external;

    function bingo(
        uint256 gameId,
        uint8[][] calldata cardNumbers,
        bytes calldata signedLabel
    ) external;

    function selectAndBingo(
        uint256 gameId,
        uint8 number,
        uint8[][] calldata cardNumbers,
        bytes calldata signedLabel
    ) external;

    /**
     * @dev Call this function by callStatic to check if a game is ongoing and
     *      check if cached card content is available
     */
    function restoreGame(
        address player,
        uint8[][] memory cardNumbers,
        bytes memory signedGameLabel
    ) external returns (
        uint256 playingGameId,
        uint32 autoEndTime,
        bool isCardContentMatched
    );

    /*
    ██       ██████   ██████  ███████
    ██      ██    ██ ██       ██
    ██      ██    ██ ██   ███ ███████ - recentGames: all games
    ██      ██    ██ ██    ██      ██ - playedGames: player's games
    ███████  ██████   ██████  ███████ - summary: total games, players, rewards
    */

    struct RecentGame {
        uint256 gameId;
        string status;
        address winner;
        uint8[][] cardNumbers;
        uint8[] selectedNumbers;
        Participant[] players;
    }

    function recentGames(RecentGameFilter filter) external view returns (
        RecentGame[] memory games
    );

    function playedGames(address player, uint256 skip) external view returns (
        RecentGame[] memory games
    );

   /**
    * @return totalGameStarted - total games started
    * @return totalPlayersJoined - total players joined
    * @return totalRewardDistributed - total reward(NFTs) distributed
    */
    function summary() external view returns (
        uint256 totalGameStarted,
        uint256 totalPlayersJoined,
        uint256 totalRewardDistributed
    );
}

