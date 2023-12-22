// SPDX-License-Identifier: MIT
//  ______           _                ______             _          _
// (_____ \      _  (_)              (_____ \           (_)        | |
//  _____) )__ _| |_ _  ___  ____     _____) )____ ____  _  ____   | |
// |  ____/ _ (_   _) |/ _ \|  _ \   |  ____(____ |  _ \| |/ ___)  |_|
// | |   | |_| || |_| | |_| | | | |  | |    / ___ | | | | ( (___    _
// |_|    \___/  \__)_|\___/|_| |_|  |_|    \_____|_| |_|_|\____)  |_|
//

pragma solidity >=0.8.0;

import {IERC20} from "./ERC20_IERC20.sol";
import {IFeeCollector} from "./IFeeCollector.sol";
import {IElixETH} from "./IElixETH.sol";
import {Operatable} from "./Operatable.sol";
import {IPlayerCard} from "./IPlayerCard.sol";

/// @title PotionPanic
/// @author 0xCalibur
/// @author Inspired by the Bullet Game Dark Portal Telegram game.
/// @notice Game Mechanism: The winner takes all the bets minus the fee.
contract PotionPanic is Operatable {
    error ErrInvalidFeeBips();
    error ErrInvalidFeeOperator(address);

    error ErrInvalidNumIngredients();
    error ErrProofNotMatching();
    error ErrAlreadyStarted();
    error ErrInvalidNumPlayers();
    error ErrNotStarted();
    error ErrInvalidBetAmount();
    error ErrInvalidWinner();
    error ErrInvalidTipAmount();
    error ErrCannotCoverTransactionFee();
    error ErrInvalidUserdata();
    error ErrUnauthorized();

    event LogStarted(uint256 betAmount, uint8 numIngredients, address[] players, bytes32 commitment);
    event LogEnded(address indexed winner, uint256 rewards, uint256 fee, bytes proof);
    event LogTipped(address indexed from, address indexed to, uint256 amount);
    event LogRegister(address indexed sender, uint256 code);
    event LogAborted();
    event LogFeeParametersChanged(address indexed feeCollector, uint16 feeAmount);
    event LogHardMinBetChanged(uint256 amount);
    event LogAccountCreated(address indexed account, uint256 id);

    IERC20 public immutable token;
    IPlayerCard public immutable card;

    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    /// Global Parameters
    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    uint16 public feeBips;
    address public feeCollector;
    uint256 public hardMinBet;

    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    /// Game State
    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    bool public started;
    uint8 public numIngredients;
    bytes32 public commitment;
    uint256 public bet;
    address[] public players;
    mapping(address user => bool active) public playerMap;

    constructor(IERC20 _token, IPlayerCard _card, address _owner) Operatable(_owner) {
        token = _token;
        card = _card;
    }

    /// @notice Used to get the number of bets.
    function playerLength() public view returns (uint256) {
        return players.length;
    }

    /// @notice Link a player to an address,
    /// optionally mint some ElixETH
    function register(uint256 _code) external payable returns (uint256 id) {
        id = card.idOf(msg.sender);

        if (msg.value > 0) {
            IElixETH(address(token)).depositTo{value: msg.value}(msg.sender);
        }

        // user doesn't have a card, mint one
        if (id == 0) {
            id = card.mint(msg.sender);
            emit LogAccountCreated(msg.sender, id);
        }
        emit LogRegister(msg.sender, _code);
    }

    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    /// Operator functions
    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-

    /// @notice Starts a game instance, only one can be active at a time.
    /// @param _players The players.
    /// @param _bet The bet amount.
    /// @param _numIngredients The number of ingredients.
    /// @param _commitment The commitment of the game. Hash composed of the random number and the salts.
    /// When the game ends, the random number will be revealed along with the salts to verify the commitment.
    function start(address[] memory _players, uint256 _bet, uint8 _numIngredients, bytes32 _commitment) external onlyOperators {
        if (started) {
            revert ErrAlreadyStarted();
        }
        if (_numIngredients < 2) {
            revert ErrInvalidNumIngredients();
        }
        if (_players.length < 2 || _players.length > _numIngredients) {
            revert ErrInvalidNumPlayers();
        }
        if (_bet < hardMinBet) {
            revert ErrInvalidBetAmount();
        }

        started = true;
        numIngredients = _numIngredients;
        commitment = _commitment;
        bet = _bet;
        players = _players;

        for (uint256 i = 0; i < _players.length; ) {
            if (card.idOf(_players[i]) == 0) {
                revert ErrUnauthorized();
            }

            playerMap[_players[i]] = true;
            token.transferFrom(_players[i], address(this), _bet);

            unchecked {
                ++i;
            }
        }

        emit LogStarted(_bet, _numIngredients, _players, _commitment);
    }

    /// @notice End the game and distribute the rewards from the loser's bet
    /// @param winner The address of the winner.
    /// @param _proof The proof of the commitment, composed of the random number and the salts.
    function end(address winner, bytes memory _proof, bytes[] calldata userdata) external onlyOperators returns (uint256 winnerReward) {
        if (!started) {
            revert ErrNotStarted();
        }
        if (!playerMap[winner]) {
            revert ErrInvalidWinner();
        }
        if (players.length != userdata.length) {
            revert ErrInvalidUserdata();
        }
        if (keccak256(_proof) != commitment) {
            revert ErrProofNotMatching();
        }

        winnerReward = bet * players.length;
        uint256 fee = (winnerReward * feeBips) / 10_000;
        winnerReward -= fee;

        // redistribute the bet amount to the winning players
        for (uint256 i = 0; i < players.length; ) {
            delete playerMap[players[i]];

            // update player's card
            card.updateOwnerData(players[i], userdata[i]);

            unchecked {
                ++i;
            }
        }

        // return winner's reward
        token.transfer(winner, winnerReward);

        IElixETH(address(token)).withdrawTo(feeCollector, fee);
        _resetState();

        emit LogEnded(winner, winnerReward, fee, _proof);
    }

    /// @notice This function is used to abort the game.
    function abort() external onlyOperators {
        if (!started) {
            revert ErrNotStarted();
        }

        // refund users
        for (uint256 i = 0; i < players.length; i++) {
            delete playerMap[players[i]];
            token.transfer(players[i], bet);
        }

        _resetState();
        emit LogAborted();
    }

    /// @notice This function is used to set the minimum bet amount.
    /// @param _hardMinBet The minimum bet amount.
    function setHardMinBet(uint256 _hardMinBet) external onlyOperators {
        hardMinBet = _hardMinBet;
        emit LogHardMinBetChanged(_hardMinBet);
    }

    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    /// Admin functions
    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-

    /// @notice This function is used to set the fee parameters.
    /// @param _feeCollector The address of the fee collector.
    /// @param _feeBips The fee amount in bips.
    function setFeeParameters(address _feeCollector, uint16 _feeBips) external onlyOwner {
        if (feeBips > 10_000) {
            revert ErrInvalidFeeBips();
        }

        feeCollector = _feeCollector;
        feeBips = _feeBips;

        emit LogFeeParametersChanged(_feeCollector, _feeBips);
    }

    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-
    /// Private functions
    /// -=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=--=-=-=-=-=-=-

    /// @notice This function is used to reset the game state.
    function _resetState() private {
        delete players;
        delete numIngredients;
        delete commitment;
        delete bet;
        started = false;
    }
}

