// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.9;

import "./IERC20.sol";
import {OwnableOracle} from "./OwnableOracle.sol";
import "./Pausable.sol";

contract TekkenWager is OwnableOracle, Pausable {
    struct Game {
        address creator;
        address opponent;
        uint256 wagerAmount;
        uint256 startTime;
        bool hasStarted;
    }

    mapping(uint256 gameId => Game game) public games;
    mapping(address player => uint256 gameId) public currentGame;

    uint256 public minimumDMT;
    uint256 public maximumDMT;
    uint256 public cancelTime;

    uint256 private gameIdCounter;
    uint256 private feePercentage; // Measured in 1000ths. So 25 => 2.5%, 250 => 25%
    IERC20 private DMT;

    event GameCreated(uint256 indexed id, address indexed creator, uint256 wagerAmount);
    event GameJoined(uint256 indexed id, address indexed opponent);
    event GameDecided(uint256 indexed id, address indexed winner, uint256 payout);
    event GameCancelled(uint256 indexed id, address indexed creator, uint256 wagerAmount);

    modifier notInGame() {
        require(isInGame(msg.sender) == false, "You are in a game already");
        _;
    }

    constructor(uint256 _feePercentage, IERC20 _DMT, address _oracle, uint256 _cancelTime) OwnableOracle(_oracle) {
        feePercentage = _feePercentage;
        DMT = _DMT;
        cancelTime = _cancelTime;
    }

    function createPendingGame(address _opponent, uint256 _wagerAmount) external notInGame whenNotPaused {
        require(
            _wagerAmount >= minimumDMT && _wagerAmount <= maximumDMT, "Wager amount is not within the allowed range"
        );

        gameIdCounter++;

        payWager(_wagerAmount);

        Game memory newGame =
            Game({startTime: 0, creator: msg.sender, opponent: _opponent, wagerAmount: _wagerAmount, hasStarted: false});
        games[gameIdCounter] = newGame;

        currentGame[msg.sender] = gameIdCounter;

        emit GameCreated(gameIdCounter, msg.sender, _wagerAmount);
    }

    function joinPendingGame(uint256 _gameId) external notInGame whenNotPaused {
        Game storage game = games[_gameId];

        require(_gameId != 0 && game.creator != address(0), "Invalid game ID");
        require(game.opponent == address(0) || game.opponent == msg.sender, "You are not the specified opponent");
        require(game.creator != msg.sender, "You cannot join your own game");

        payWager(game.wagerAmount);

        game.opponent = msg.sender;
        game.startTime = block.timestamp;
        game.hasStarted = true;

        currentGame[msg.sender] = _gameId;

        emit GameJoined(_gameId, msg.sender);
    }

    function cancelGame() external {
        uint256 _gameId = currentGame[msg.sender];
        require(_gameId != 0, "You are not in a game");

        Game memory game = games[_gameId];
        if (game.hasStarted == false) {
            require(game.creator == msg.sender, "Only the creator can cancel the game");
            require(DMT.transfer(game.creator, game.wagerAmount), "Token transfer failed");
            currentGame[game.creator] = 0;
        } else {
            require(
                block.timestamp >= game.startTime + cancelTime,
                "Game must have been started for at least the cancelTime"
            );
            require(game.creator != address(0) && game.opponent != address(0), "Game is invalid");
            require(DMT.transfer(game.creator, game.wagerAmount), "Token transfer failed");
            require(DMT.transfer(game.opponent, game.wagerAmount), "Token transfer failed");
            currentGame[game.creator] = 0;
            currentGame[game.opponent] = 0;
        }
        delete games[_gameId];

        emit GameCancelled(_gameId, msg.sender, game.wagerAmount);
    }

    function decideGame(uint256 _gameId, address _winner) external onlyOracle {
        Game memory game = games[_gameId];
        require(_gameId != 0 || game.creator != address(0) || game.opponent != address(0), "Invalid game ID");
        require(game.hasStarted == true, "Game must have started");
        require(
            _winner == game.creator || _winner == game.opponent || _winner == address(0),
            "Winner must be one of the players or address(0)"
        );

        currentGame[game.creator] = 0;
        currentGame[game.opponent] = 0;

        if (_winner == address(0)) {
            // draw
            require(DMT.transfer(game.creator, game.wagerAmount), "Token transfer failed");
            require(DMT.transfer(game.opponent, game.wagerAmount), "Token transfer failed");

            emit GameDecided(_gameId, _winner, 0);
        } else {
            // winner
            uint256 payout = game.wagerAmount * 2;
            if (feePercentage > 0) {
                uint256 fee = (payout * feePercentage) / 1000;
                payout -= fee;
                require(DMT.transfer(address(owner()), fee), "Fee transfer failed");
            }

            require(DMT.transfer(_winner, payout), "Payout transfer failed");

            emit GameDecided(_gameId, _winner, payout);
        }
        delete games[_gameId];
    }

    function updateFee(uint256 _feePercentage) external onlyOwner {
        feePercentage = _feePercentage;
    }

    function updateMaxMinDMT(uint256 _minimumDMT, uint256 _maximumDMT) external onlyOwner {
        minimumDMT = _minimumDMT;
        maximumDMT = _maximumDMT;
    }

    function updateCancelTime(uint256 _cancelTime) external onlyOwner {
        cancelTime = _cancelTime;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function isInGame(address _player) public view returns (bool) {
        return currentGame[_player] != 0;
    }

    function payWager(uint256 _wagerAmount) private {
        require(DMT.transferFrom(msg.sender, address(this), _wagerAmount), "Token transfer failed");
    }
}

