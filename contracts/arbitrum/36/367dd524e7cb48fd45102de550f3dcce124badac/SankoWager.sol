// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.19;

// import "forge-std/interfaces/IERC20.sol";
import "./IERC20.sol";
import "./Pausable.sol";
import "./Math.sol";
import {OwnableOracle} from "./OwnableOracle.sol";
import {FeeCollection, Fee} from "./FeeCollection.sol";
// import {SwapAndSend} from "./SwapAndSend.sol";

contract SankoWager is FeeCollection, OwnableOracle, Pausable {
    struct SankoWagerGame {
        uint256 wagerAmount;
        address[] players;
    }

    mapping(uint256 gameId => SankoWagerGame game) public games;
    mapping(address player => uint256 gameId) public currentGame;

    uint256 public minimumDMT;
    uint256 public maximumDMT;

    uint256 private gameIdCounter;
    uint256 private maxPlayers;

    IERC20 private DMT;

    event GameStarted(uint256 indexed id, uint256 wagerAmount);
    event GameJoined(uint256 indexed id, address indexed player);
    event GameDecided(uint256 indexed id, address indexed winner, uint256 payout);

    modifier notInGame(address[] calldata _players) {
        for (uint256 i = 0; i < _players.length; i++) {
            require(isInGame(_players[i]) == false, "At least one player is already in a game");
        }
        _;
    }

    modifier validAddresses(address[] calldata _players) {
        for (uint256 i = 0; i < _players.length; i++) {
            require(_players[i] != address(0), "Player cannot be address(0)");
        }
        _;
    }

    constructor(IERC20 _DMT, address _oracle)
        // SwapAndSend(_camelotRouter, _usdc)
        OwnableOracle(_oracle)
    {
        DMT = _DMT;
        setFeeToken(_DMT);
    }

    function createGame(uint256 _wagerAmount, address[] calldata _players)
        external
        whenNotPaused
        notInGame(_players)
        validAddresses(_players)
        onlyOracle
    {
        uint256 numPlayers = _players.length;
        require(numPlayers >= 2 && numPlayers <= 10, "Need between 2 and 10 players");
        require(
            minimumDMT <= _wagerAmount && _wagerAmount <= maximumDMT, "Wager amount is not within the allowed range"
        );

        gameIdCounter++;

        games[gameIdCounter] = SankoWagerGame({players: _players, wagerAmount: _wagerAmount});

        emit GameStarted(gameIdCounter, _wagerAmount);
        for (uint256 i = 0; i < _players.length; i++) {
            address player = _players[i];
            payWager(_wagerAmount, player);
            currentGame[player] = gameIdCounter;
            emit GameJoined(gameIdCounter, player);
        }
    }

    function decideGame(uint256 _gameId, address _winner) external onlyOracle {
        SankoWagerGame memory game = games[_gameId];
        require(_gameId != 0 && game.players.length != 0, "Invalid game ID");
        require(
            gameContainsPlayer(_gameId, _winner) || _winner == address(0),
            "Winner must be one of the players or address(0)"
        );

        if (_winner == address(0)) {
            // draw
            refundPlayers(game);
            emit GameDecided(_gameId, _winner, 0);
        } else {
            // winner
            uint256 payout = game.wagerAmount * game.players.length;
            Fee memory fee = calculateFee(payout);
            payout -= fee.totalAmount;
            burnFee(fee.burnAmount);
            saveFee(fee.gasAmount);
            require(DMT.transfer(_winner, payout), "Payout transfer failed");
            emit GameDecided(_gameId, _winner, payout);
        }
        // TODO
        // reimburseOracle();
        releasePlayers(game);
        delete games[_gameId];
    }

    function withdrawGasFees() external onlyOwner {
        withdrawFees(msg.sender);
    }

    function updateFeePercentage(uint256 _feePercentage) external onlyOwner {
        setFeePercentage(_feePercentage);
    }

    function updateOracleFee(uint256 _oracleFee) external onlyOwner {
        setOracleFee(_oracleFee);
    }

    function updateMaxMinDMT(uint256 _minimumDMT, uint256 _maximumDMT) external onlyOwner {
        minimumDMT = _minimumDMT;
        maximumDMT = _maximumDMT;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getGamePlayers(uint256 _gameId) external view returns (address[] memory) {
        return games[_gameId].players;
    }

    function isInGame(address _player) public view returns (bool) {
        return currentGame[_player] != 0;
    }

    function payWager(uint256 _wagerAmount, address _player) private {
        require(DMT.transferFrom(_player, address(this), _wagerAmount), "Token transfer failed");
    }

    function refundPlayers(SankoWagerGame memory game) private {
        for (uint256 i = 0; i < game.players.length; i++) {
            require(DMT.transfer(game.players[i], game.wagerAmount), "Token transfer failed");
        }
    }

    function releasePlayers(SankoWagerGame memory game) private {
        for (uint256 i = 0; i < game.players.length; i++) {
            currentGame[game.players[i]] = 0;
        }
    }

    // TODO: Implement automatic reimbursement
    // function reimburseOracle() private {
    //     if (oracle.balance < 0.05 ether) {
    //         // Swap a maximum of 5 DMT
    //         uint256 feesToSwap = Math.min(DMT.balanceOf(address(this)), 5 * DMT.decimals());
    //
    //         // These calls will not revert if they fail.
    //         if (!isSellingCollectedFees) {
    //             convertFeesToWETH(feesToSwap);
    //         }
    //         sendWETHBalanceAsETH(oracle);
    //     }
    // }

    function gameContainsPlayer(uint256 _gameId, address _player) private view returns (bool) {
        return currentGame[_player] == _gameId;
    }
}

