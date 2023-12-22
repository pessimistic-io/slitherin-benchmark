// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// solhint-disable max-line-length
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { StringsUpgradeable } from "./StringsUpgradeable.sol";
// solhint-enable max-line-length

import { BingoGameRoom, IBingoCard } from "./BingoGameRoom.sol";
import { GameLineup } from "./GameLineup.sol";
import { UserCenter } from "./UserCenter.sol";

/**
 * @dev Lobby -> Games -> Bingo Cards
 */
contract ZkBingoLobby is
    GameLineup,
    BingoGameRoom,
    UserCenter,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    string public constant NAME = "zBingo";

    uint256 public constant GAME_REWARD_FEE = 0.1 ether; // 10%

    uint32 public version;

    uint8 public minPlayers;
    uint8 public maxPlayers;

    function initialize(
        address _gameCard,
        uint8 _expectedLines,
        uint8 _minPlayers,
        uint8 _maxPlayers,
        uint8 minCardNumber,
        uint8 maxCardNumber
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        initBingoGameRoom(
            _gameCard,
            _expectedLines,
            minCardNumber,
            maxCardNumber,

            10 seconds, // game start timeout
            9, // boost first N rounds (no gap times)
            10 seconds, // round gap time
            30 seconds, // round timeout
            30 minutes // Max game duration
        );
        initGameLineup();
        initUserCenter("Early Access");

        version = 1;

        minPlayers = _minPlayers;
        maxPlayers = _maxPlayers;
    }

    function join(bytes memory zkCard) external override nonReentrant {
        _joinLineup(_msgSender(), zkCard);
        _haltPlayerLastGame(_msgSender(), false);

        require(
            !_isGameOngoing(_playerLastGameId(_msgSender())),
            "Lobby: last game is ongoing"
        );

        (
            uint8 waitings,
            /* uint256 fromIndex */,
            /* uint256 toIndex */
        ) = _lineupCounts();

        if (waitings >= maxPlayers) {
            Lineup[] memory roomUsers = _completeLineup(maxPlayers);
            uint256 gameId = _startGame(roomUsers);
            _afterGameStarted(gameId, _msgSender());
        }
    }

    function leave() external override nonReentrant {
        _leaveLineup(_msgSender());
    }

    function start() external override nonReentrant {
        require(_userInLineup(_msgSender()), "Lobby: only lineup user can start");

        (
            uint8 waitings,
            /* uint256 fromIndex */,
            /* uint256 toIndex */
        ) = _lineupCounts();

        require(waitings >= minPlayers, "Not enough players");

        Lineup[] memory roomUsers = _completeLineup(waitings);
        uint256 gameId = _startGame(roomUsers);
        _afterGameStarted(gameId, _msgSender());
    }

    function selectNumber(
        uint256 gameId,
        uint8 number
    ) external override nonReentrant onlyOngoingGame(gameId) {
        _selectNumber(gameId, _msgSender(), number);
    }

    function bingo(
        uint256 gameId,
        uint8[][] memory cardNumbers,
        bytes memory signedGameLabel
    ) external override nonReentrant onlyOngoingGame(gameId) {
        _bingo(
            gameId,
            _msgSender(),
            cardNumbers,
            bytes(keyLabel(_userJoinedCounts(_msgSender()))),
            signedGameLabel
        );

        _afterGameWon(gameId);
        _logGameWon(_msgSender());
    }

    function selectAndBingo(
        uint256 gameId,
        uint8 number,
        uint8[][] calldata cardNumbers,
        bytes calldata signedGameLabel
    ) external override onlyOngoingGame(gameId) {
        _selectNumber(gameId, _msgSender(), number);

        _bingo(
            gameId,
            _msgSender(),
            cardNumbers,
            bytes(keyLabel(_userJoinedCounts(_msgSender()))),
            signedGameLabel
        );

        _afterGameWon(gameId);
        _logGameWon(_msgSender());
    }

    function getNextKeyLabel(address user) public view returns (string memory) {
        return keyLabel(_userJoinedCounts(user) + 1);
    }

    function keyLabel(uint256 nonce) private view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    NAME,
                    "@",
                    StringsUpgradeable.toHexString(address(this)),
                    "#",
                    StringsUpgradeable.toString(nonce)
                )
            );
    }

    function fee() external view returns (uint256 value, uint256 deno) {
        version; // avoid warning this function is pure
        return (GAME_REWARD_FEE, 1 ether);
    }

    function _startGame(Lineup[] memory joiners) internal returns (uint256 gameId) {
        address[] memory players = new address[](joiners.length);
        for (uint256 i = 0; i < joiners.length; i++) {
            players[i] = joiners[i].user;
        }
        gameId = _newGame(players);

        for (uint256 i = 0; i < joiners.length; i++) {
            _joinGame(gameId, joiners[i].user, joiners[i].zkContent);
            _logGamePlayed(joiners[i].user);
        }
    }

    function _afterGameWon(uint256 gameId) internal {
        // TODO: Notice external contract
    }

    // solhint-disable-next-line no-empty-blocks
    function _afterGameStarted(uint256 gameId, address starter) internal virtual {}

    function setReward(
        address newReward,
        uint32 amount
    ) external onlyOwner {
        _setReward(newReward, amount);
    }

    function newSeason(string memory title) external onlyOwner {
        _newSeason(title);
    }

    function setGameTimers(
        uint32 startTimeout,
        uint8 boostRounds,
        uint32 roundGap,
        uint32 roundTimeout,
        uint32 maxDuration
    ) external onlyOwner {
        _setGameTimer(
            startTimeout,
            boostRounds,
            roundGap,
            roundTimeout,
            maxDuration
        );
    }

    function _authorizeUpgrade(address /* newImplementation */) internal override onlyOwner {
        version++;
    }

    /**
     * @dev Call this function by callStatic to check if a game is ongoing and
     *      check if cached card content is available
     */
    function restoreGame(
        address player,
        uint8[][] memory cardNumbers,
        bytes memory signedGameLabel
    ) external override returns (
        uint256 playingGameId,
        uint32 autoEndTime,
        bool isCardContentMatched
    ) {
        playingGameId = _playerLastGameId(player);

        if (!_isGameOngoing(playingGameId)) {
            return (0, 0, false);
        }

        autoEndTime = _gameAutoEndTime(playingGameId);

        uint256 cardId = _playerCardId(playingGameId, player);

        try IBingoCard(gameCard()).reveal(
            cardId,
            bytes(keyLabel(_userJoinedCounts(player))),
            signedGameLabel,
            cardNumbers
        ) {
            // Do nothing
        } catch {
            // Invalid params
            return (playingGameId, autoEndTime, false);
        }

        try IBingoCard(gameCard()).getCardNumbers(cardId) returns (uint8[][] memory) {
            return (playingGameId, autoEndTime, true);
        } catch {
            // Not revealed
            return (playingGameId, autoEndTime, false);
        }
    }
}

