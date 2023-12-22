// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IBingoCard } from "./IBingoCard.sol";
import { IBingoRoom } from "./IBingoRoom.sol";

string constant GAME_INVALID = "invalid";
string constant GAME_BINGOED = "end";
string constant GAME_OVERTIME = "overtime";
string constant GAME_ONGOING = "live";

interface Rewardable {
    function mint(address to) external;
}

abstract contract BingoGameRoom is IBingoRoom {
    struct Game {
        uint256 selectedNumbers;
        uint256 winnerCardId;
        address winner;
        uint32 startedAt;
        uint32 endedAt;
    }

    /**
     * @dev
     *   Game Started | startTimeour | boostRounds x roundTimeout | roundGap + roundTimeout | ...
     */
    struct GameTimeout {
        uint32 startTimeout;
        uint8 boostRounds; // no gap between rounds for first N rounds

        uint32 roundGap;
        uint32 roundTimeout;

        uint32 maxDuration;
        // uint120 __gap;
    }
    GameTimeout internal _timer;

    uint8 public constant RECENT_GAME_COUNTS = 20;

    IBingoCard private _gameCard;
    uint8 private _expectedLines;
    uint8 private _minNumber;
    uint8 private _maxNumber;

    /** @dev gameId <= _firstGameId are all ended */
    uint256 private _firstGameId;
    /** @dev game counts that already created */
    uint256 private _lastGameId;
    mapping(uint256 => Game) private _games;
    mapping(uint256 => GameRound[]) private _gameRounds;
    mapping(uint256 => Participant[]) private _gameParticipants;
    mapping(address => uint256[]) private _gamePlayed;


    struct RewardInfo {
        address token; // 20 bytes
        uint32 maxDistribution;
        // uint64 __gap;
    }
    RewardInfo private _reward;
    mapping(address => uint256) private _rewardDistributed;
    uint256 private _totalPlayers;

    /** @dev Update _firstGameId to the closest point of ongoing games */
    modifier autoStopOvertimeGames() {
        bool found = false;
        uint32 autoStopTime = _overtimeGameStart();

        while (_firstGameId < _lastGameId) {
            Game storage firstGame = _games[_firstGameId];

            if (firstGame.endedAt == 0) {
                // Current game not yet marked as ended:

                // 1. Not over the time limit, skip it and stop the loop.
                if (firstGame.startedAt > autoStopTime) break;

                // 2. Over the time limit, but we already change 1 game, stop the loop.
                //    (we should not change too many storage in one transaction)
                if (found) break;
            }

            // Possible firstGame state:
            // 1. Already ended
            // 2. Not ended but overtime

            if (
                firstGame.endedAt == 0 &&
                firstGame.startedAt < autoStopTime
            ) {
                firstGame.endedAt = uint32(block.timestamp);
                found = true;

                emit GameHalted(_firstGameId, msg.sender, true);
            }

            _firstGameId++;
        }

        _;
    }

    modifier onlyOngoingGame(uint256 gameId) {
        require(_isGameOngoing(gameId), "BingoGameRoom: !playing");
        _;
    }

    function initBingoGameRoom(
        address cardContract,
        uint8 expectedLines_,
        uint8 minNumber_,
        uint8 maxNumber_,

        uint32 startTimeout,
        uint8 boostRounds,
        uint32 roundGap,
        uint32 roundTimeout,
        uint32 maxDuration
    ) internal {
        _gameCard = IBingoCard(cardContract);
        _expectedLines = expectedLines_;
        _minNumber = minNumber_;
        _maxNumber = maxNumber_;

        _setGameTimer(
            startTimeout,
            boostRounds,
            roundGap,
            roundTimeout,
            maxDuration
        );
    }

    function gameCard() public view override returns (address) {
        return address(_gameCard);
    }

    function expectedLines() public view override returns (uint8) {
        return _expectedLines;
    }

    function _newGame(address[] memory players) internal autoStopOvertimeGames returns (uint256 gameId) {
        gameId = ++_lastGameId;
        _games[gameId].startedAt = uint32(block.timestamp);

        emit GameStarted(gameId, address(_gameCard), players);
    }

    function _playerLastGameId(address user) internal view returns (uint256 gameId) {
        if (_gamePlayed[user].length > 0) {
            gameId = _gamePlayed[user][_gamePlayed[user].length - 1];
        }
    }

    function _joinGame(uint256 gameId, address user, bytes memory entryptedCard) internal {
        uint256 cardId = _gameCard.mint(user, gameId, entryptedCard);

        _gameParticipants[gameId].push(Participant(user, cardId));
        _gamePlayed[user].push(gameId);
        _totalPlayers++;

        emit GameParticipated(
            gameId,
            user,
            cardId,
            uint8(_gameParticipants[gameId].length)
        );
    }

    function getGameInfo(uint256 gameId) public view override returns (
        uint32 startedAt,
        uint32 endedAt,
        address winner,
        Participant[] memory players,
        GameRound[] memory rounds,
        string memory status
    ) {
        status = GAME_INVALID;
        if (_hasGameRecord(gameId)) {
            startedAt = _games[gameId].startedAt;
            endedAt = _games[gameId].endedAt;

            players = _gameParticipants[gameId];
            rounds = _gameRounds[gameId];

            if (_games[gameId].winner != address(0)) {
                winner = _games[gameId].winner;
                status = GAME_BINGOED;
            } else if (_games[gameId].endedAt > 0 || _games[gameId].startedAt < _overtimeGameStart()) {
                status = GAME_OVERTIME;
            } else {
                status = GAME_ONGOING;
            }
        }
    }

    /**
     * @dev
     *   last round (R0) | Timeout to sync |     R0 + 1      |     R0 + 2      | ...
     *      <lastTime>   |  +ROUND_TIMEOUT | +ROUND_DURATION | +ROUND_DURATION | ...
     */
    function getCurrentRound(
        uint256 gameId
    ) public view override returns (
        uint32 round,
        address player,
        uint32 remain,
        string memory status
    ) {
        require(_hasGameRecord(gameId), "!exists");

        GameRound memory lastRound = getLatestRound(gameId);

        // Game ended, return the last round, and no player can select number.
        if (_games[gameId].winner != address(0)) return (lastRound.round, address(0), 0, GAME_BINGOED);
        if (
            _games[gameId].endedAt > 0 ||
            _games[gameId].startedAt < _overtimeGameStart()
        ) return (lastRound.round, address(0), 0, GAME_OVERTIME);

        // Before 1 round
        if (
            lastRound.round == 0 &&
            _games[gameId].startedAt + _timer.startTimeout > block.timestamp
        ) return (
            0,
            address(0),
            _games[gameId].startedAt + _timer.startTimeout - uint32(block.timestamp),
            GAME_ONGOING
        );

        uint32 r0 = lastRound.round + 1;

        uint256 lastTime = r0 > 1
            ? uint256(lastRound.timestamp)
            : uint256(_games[gameId].startedAt + _timer.startTimeout);

        uint256 timePassed = block.timestamp - lastTime;

        // Selected numbers more than boostRounds, then gap between rounds for Bingo players.
        uint32 gapTime = _gameRounds[gameId].length > _timer.boostRounds
            ? _timer.roundGap
            : 0;

        // Not over the gap time, new round, but no player can select number.
        if (timePassed < gapTime) {
            return (
                r0,
                address(0),
                uint32(gapTime - timePassed) + _timer.roundTimeout,
                GAME_ONGOING
            );
        }

        round = r0 + uint32((timePassed - gapTime) / _timer.roundTimeout);
        remain = _timer.roundTimeout - uint32((timePassed - gapTime) % _timer.roundTimeout);

        player = _getRoundPlayer(gameId, round);

        return (round, player, remain, GAME_ONGOING);
    }

    function getSelectedNumbers(
        uint256 gameId
    ) external view returns (uint8[] memory numbers) {
        if (_hasGameRecord(gameId)) {
            return _gameCard.decodeSelectedNumbers(
                _games[gameId].selectedNumbers
            );
        }
    }

    function getLatestRound(uint256 gameId) public view returns (GameRound memory last) {
        uint256 counts = _gameRounds[gameId].length;

        if (counts > 0) {
            last = _gameRounds[gameId][counts - 1];
        }
    }

    function _getRoundPlayer(uint256 gameId, uint32 round) internal view returns (address) {
        return _getRoundPlayerInOrder(gameId, round);
    }

    function _getRoundPlayerInOrder(uint256 gameId, uint32 round) internal view returns (address) {
        uint256 playerCounts = _gameParticipants[gameId].length;
        return _gameParticipants[gameId][(round - 1) % playerCounts].user;
    }

    /**
     * @dev players.length = N (counts)
     *
     *   player 0 |  player 1 |  ...  |  player N-1
     *   #1 (r=0) -> #2       -> ...  -> #N   (r = N - 1)
     *   #2N                     ... <-  #N+1 (r = N)
     */
    function _getRoundPlayerInZ(uint256 gameId, uint32 round) internal view returns (address) {
        uint256 playerCounts = _gameParticipants[gameId].length;
        uint256 r = (round - 1) % (2 * playerCounts);

        return r >= playerCounts
            ? _gameParticipants[gameId][playerCounts * 2 - r - 1].user
            : _gameParticipants[gameId][r].user;
    }

    function _selectNumber(
        uint256 gameId,
        address player,
        uint8 number
    ) internal {
        require(_isGameOngoing(gameId), "BingoGameRoom: not playing");
        uint8 order = uint8(_gameRounds[gameId].length + 1);
        require(_isSelectableNumber(number, order), "BingoGameRoom: unselectable");

        (
            uint32 round,
            address roundPlayer,
            /* uint32 remain */,
            /* string memory status */
        ) = getCurrentRound(gameId);
        require(player == roundPlayer, "BingoGameRoom: not your turn");

        uint256 selected = _games[gameId].selectedNumbers;

        uint8[] memory nums = new uint8[](1);
        nums[0] = number;

        uint256 toSelect = _gameCard.encodeSelectedNumbers(nums);
        require(selected & toSelect == 0, "BingoGameRoom: already selected");

        _games[gameId].selectedNumbers = selected | toSelect;
        _gameRounds[gameId].push(
            GameRound(
                round,
                number,
                uint32(block.timestamp),
                player
            )
        );
        emit NumberSelected(gameId, round, player, number);
    }

    function _bingo(
        uint256 gameId,
        address player,
        uint8[][] memory numbers,
        bytes memory gameLabel,
        bytes memory signedGameLabel
    ) internal {
        require(_isGameOngoing(gameId), "BingoGameRoom: not playing");

        Participant memory winner;
        for (uint256 i = 0; i < _gameParticipants[gameId].length; i++) {
            if (_gameParticipants[gameId][i].user == player) {
                winner = _gameParticipants[gameId][i];
                break;
            }
        }

        _gameCard.reveal(
            winner.cardId,
            gameLabel,
            signedGameLabel,
            numbers
        );

        require(
            _gameCard.calculateMatchedLineCounts(
                _gameCard.getCardNumbers(winner.cardId),
                _games[gameId].selectedNumbers
            ) >= expectedLines(),
            "BingoGameRoom: Not enough lines"
        );

        _games[gameId].endedAt = uint32(block.timestamp);
        _games[gameId].winner = player;
        _games[gameId].winnerCardId = winner.cardId;

        emit Bingo(gameId, player, numbers);
        _distributeReward(player);
    }

    function _isGameOngoing(uint256 gameId) internal view returns (bool) {
        Game storage game = _games[gameId];
        return game.startedAt > 0
            && game.endedAt == 0
            && game.startedAt > _overtimeGameStart();
    }

    /** @dev game.startedAt > _overtimeGameStart() is suppose to be stopped by the system */
    function _overtimeGameStart() internal view returns (uint32) {
        return uint32(block.timestamp - _timer.maxDuration);
    }

    /**
     * @dev In some Bingo rules, selectable numbers are restricted by the order.
     *      For these rules, please override this function.
     */
    function _isSelectableNumber(
        uint8 number,
        uint8 order
    ) internal view virtual returns (bool) {
        return order > 0 && number >= _minNumber && number <= _maxNumber;
    }

    function _hasGameRecord(uint256 gameId) internal view returns (bool) {
        return gameId <= _lastGameId && _games[gameId].startedAt > 0;
    }

    function _gamePlayerCounts(uint256 gameId) internal view returns (uint8) {
        return uint8(_gameParticipants[gameId].length);
    }

    function _gamePlayers(uint256 gameId) internal view returns (address[] memory) {
        uint8 counts = _gamePlayerCounts(gameId);
        address[] memory players = new address[](counts);

        for (uint8 i = 0; i < counts; i++) {
            players[i] = _gameParticipants[gameId][i].user;
        }

        return players;
    }

    function summary() external view returns (
        uint256 totalGameStarted,
        uint256 totalPlayersJoined,
        uint256 totalRewardDistributed
    ) {
        return (
            _lastGameId,
            _totalPlayers,
            _rewardDistributed[_reward.token]
        );
    }

    function _setReward(address newReward, uint32 maxAmounts) internal {
        _reward = RewardInfo({
            token: newReward,
            maxDistribution: maxAmounts
        });
        emit RewardChanged(newReward, _reward.token);
    }

    function _distributeReward(address to) internal returns (bool) {
        if (
            _reward.token != address(0) &&
            _rewardDistributed[_reward.token] < _reward.maxDistribution
        ) {
            Rewardable(_reward.token).mint(to);
            _rewardDistributed[_reward.token] += 1;

            return true;
        }

        return false;
    }

    function playedGames(address user, uint256 skip) external view override returns (RecentGame[] memory games) {
        uint256 total = _gamePlayed[user].length;
        uint256 endIndex = skip > total
            ? 0
            : total - skip;
        uint256 startIndex = endIndex >= RECENT_GAME_COUNTS
            ? endIndex - RECENT_GAME_COUNTS
            : 0;

        uint256 counts = endIndex - startIndex;

        games = new RecentGame[](endIndex - startIndex);
        for (uint256 i = 0; i < counts; i++) {
            uint256 id = _gamePlayed[user][startIndex + i];
            games[i] = _isGameOngoing(id)
                ? _formatLiveGame(id)
                : _formatEndedGame(id);
        }
    }

    function recentGames(RecentGameFilter filter) public view override returns(
        RecentGame[] memory games
    ) {
        if (filter == RecentGameFilter.LIVE) return _recentLiveGames(RECENT_GAME_COUNTS);
        if (filter == RecentGameFilter.FINISHED) return _recentEndGames(RECENT_GAME_COUNTS);

        return _recentGames(RECENT_GAME_COUNTS);
    }

    function _recentLiveGames(uint8 maxCounts) internal view returns (RecentGame[] memory games) {
        uint256[] memory gameIds = new uint256[](maxCounts);
        uint8 matched = 0;

        for (
            uint256 id = _lastGameId;
            id > _firstGameId && matched < maxCounts;
            id--
        ) {
            if (!_isGameOngoing(id)) continue;
            gameIds[matched++] = id;
        }

        games = new RecentGame[](matched);
        for (uint8 i = 0; i < matched; i++) {
            games[i] = _formatLiveGame(gameIds[i]);
        }
    }

    function _recentEndGames(uint8 maxCounts) internal view returns (RecentGame[] memory games) {
        uint256[] memory gameIds = new uint256[](maxCounts);
        uint8 matched = 0;

        for (
            uint256 id = _lastGameId;
            matched < maxCounts && id > 0;
            id--
        ) {
            if (_isGameOngoing(id)) continue;
            gameIds[matched++] = id;
        }

        games = new RecentGame[](matched);
        for (uint8 i = 0; i < matched; i++) {
            games[i] = _formatEndedGame(gameIds[i]);
        }
    }

    function _recentGames(uint8 maxCounts) internal view returns (RecentGame[] memory games) {
        games = new RecentGame[](_lastGameId > maxCounts ? maxCounts : _lastGameId);

        for (uint256 i = 0; i < games.length; i++) {
            uint256 id = _lastGameId - i;
            games[i] = _isGameOngoing(id)
                ? _formatLiveGame(id)
                : _formatEndedGame(id);
        }
    }

    function _formatEndedGame(uint256 gameId) internal view returns (RecentGame memory game) {
        return RecentGame(
            gameId,
            _games[gameId].winner == address(0) ? "overtime" : "end",
            _games[gameId].winner,
            _games[gameId].winnerCardId > 0
                ? _gameCard.getCardNumbers(_games[gameId].winnerCardId)
                : new uint8[][](0),
            _gameCard.decodeSelectedNumbers(_games[gameId].selectedNumbers),
            _gameParticipants[gameId]
        );
    }

    function _formatLiveGame(uint256 gameId) internal view returns (RecentGame memory game) {
        return RecentGame(
            gameId,
            "live",
            address(0),
            new uint8[][](0),
            _gameCard.decodeSelectedNumbers(_games[gameId].selectedNumbers),
            _gameParticipants[gameId]
        );
    }

    function _setGameTimer(
        uint32 startTimeout,
        uint8 boostRounds,
        uint32 roundGap,
        uint32 roundTimeout,
        uint32 maxDuration
    ) internal {
        require(
            maxDuration >= 10 seconds &&
            maxDuration < 30 days,
            "BingoGameRoom: invalid duration"
        );

        _timer = GameTimeout({
            startTimeout: startTimeout,
            boostRounds: boostRounds,
            roundGap: roundGap,
            roundTimeout: roundTimeout,
            maxDuration: maxDuration
        });
    }

    /**
     * @dev forceStop(false) => stop last game if it's over-time
     */
    function _haltPlayerLastGame(address user, bool forceStop) internal returns (bool stoped) {
        uint256 lastGameId = _playerLastGameId(user);

        if (lastGameId == 0) return false;

        if (lastGameId == 0 || _games[lastGameId].endedAt > 0) return false;

        bool isOvertime = _games[lastGameId].startedAt < _overtimeGameStart();

        if (isOvertime || forceStop) {
            _games[lastGameId].endedAt = uint32(block.timestamp);
            emit GameHalted(lastGameId, user, isOvertime);
            return true;
        }
    }

    function timer() external view returns (GameTimeout memory) {
        return _timer;
    }

    function _gameAutoEndTime(uint256 gameId) internal view returns (uint32) {
        return _games[gameId].startedAt + _timer.maxDuration;
    }

    function _playerCardId(uint256 gameId, address user) internal view returns (uint256) {
        for (uint256 i = 0; i < _gameParticipants[gameId].length; i++) {
            if (_gameParticipants[gameId][i].user == user) {
                return _gameParticipants[gameId][i].cardId;
            }
        }
        return 0;
    }
}

