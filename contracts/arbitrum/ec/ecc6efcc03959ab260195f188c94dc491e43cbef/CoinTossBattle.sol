// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {PvPGame} from "./PvPGame.sol";

// import "hardhat/console.sol";

/// @title BetSwirl's Coin Toss battle game
/// @notice The game is played with a two-sided coin. The game's goal is to guess whether the lucky coin face will be Heads or Tails.
/// @author Romuald Hog
contract CoinTossBattle is PvPGame {
    /// @notice Coin Toss bet information struct.
    /// @param face The chosen coin face.
    /// @param rolled The rolled coin face.
    /// @dev Coin faces: true = Tails, false = Heads.
    struct CoinTossBattleBet {
        bool face;
        bool rolled;
    }

    /// @notice Maps bets IDs to CoinTossBattleBet struct.
    mapping(uint24 => CoinTossBattleBet) public coinTossBattleBets;

    /// @notice Emitted after a bet is placed.
    /// @param id The bet ID.
    /// @param player Address of the gamer.
    /// @param opponent Address of the opponent.
    /// @param token Address of the token.
    /// @param amount The bet amount.
    /// @param face The chosen coin face.
    event PlaceBet(
        uint24 id,
        address indexed player,
        address opponent,
        address indexed token,
        uint256 amount,
        bool face
    );

    /// @notice Emitted after a bet is rolled.
    /// @param id The bet ID.
    /// @param players Players addresses.
    /// @param winner Address of the winner.
    /// @param token Address of the token.
    /// @param betAmount The bet amount.
    /// @param face The chosen coin face.
    /// @param rolled The rolled coin face.
    /// @param payout The payout amount.
    event Roll(
        uint24 indexed id,
        address[] players,
        address winner,
        address indexed token,
        uint256 betAmount,
        bool face,
        bool rolled,
        uint256 payout
    );

    /// @notice Initialize the game base contract.
    /// @param chainlinkCoordinatorAddress Address of the Chainlink VRF Coordinator.
    /// @param store Address of the PvP Games Store.
    constructor(
        address chainlinkCoordinatorAddress,
        address store
    ) PvPGame(chainlinkCoordinatorAddress, store) {}

    function betMaxSeats(uint24) public pure override returns (uint256) {
        return 2;
    }

    function betMinSeats(uint24) public pure override returns (uint256) {
        return 2;
    }

    /// @notice Creates a new bet and stores the chosen coin face.
    /// @param face The chosen coin face.
    /// @param token Address of the token.
    /// @param tokenAmount The number of tokens bet.
    function wager(
        bool face,
        address token,
        uint256 tokenAmount,
        address opponent,
        bytes calldata nfts
    ) external payable whenNotPaused {
        address[] memory opponents;
        if (opponent != address(0)) {
            opponents = new address[](1);
            opponents[0] = opponent;
        } else {
            opponents = new address[](0);
        }

        Bet memory bet = _newBet(token, tokenAmount, opponents, nfts);

        coinTossBattleBets[bet.id].face = face;

        emit PlaceBet(
            bet.id,
            bet.seats[0],
            opponent,
            bet.token,
            bet.amount,
            face
        );
    }

    function joinGame(uint24 id) external payable {
        _joinGame(id, 1);
    }

    /// @notice Resolves the bet using the Chainlink randomness.
    /// @param requestId The bet ID.
    /// @param randomWords Random words list. Contains only one for this game.
    // solhint-disable-next-line private-vars-leading-underscore
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint24 id = _betsByVrfRequestId[requestId];
        CoinTossBattleBet storage coinTossBattleBet = coinTossBattleBets[id];
        Bet storage bet = bets[id];

        uint256 rolled = randomWords[0] % 2;

        bool[2] memory coinSides = [false, true];
        bool rolledCoinSide = coinSides[rolled];
        coinTossBattleBet.rolled = rolledCoinSide;
        address[] memory winners = new address[](1);
        winners[0] = rolledCoinSide == coinTossBattleBet.face
            ? bet.seats[0]
            : bet.seats[1];
        uint256 payout = _resolveBet(bet, winners, randomWords[0]);

        emit Roll(
            bet.id,
            bet.seats,
            winners[0],
            bet.token,
            bet.amount,
            coinTossBattleBet.face,
            rolledCoinSide,
            payout
        );
    }

    function getCoinTossBattleBet(
        uint24 id
    )
        external
        view
        returns (CoinTossBattleBet memory coinTossBattleBet, Bet memory bet)
    {
        return (coinTossBattleBets[id], bets[id]);
    }
}

