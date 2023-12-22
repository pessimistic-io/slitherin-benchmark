// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Core.sol";
import "./VideoPokerLogic.sol";

contract VideoPoker is Core, VideoPokerLogic {
  /*==================================================== Events ==========================================================*/

  event UpdatePayouts(uint8[9] payouts);

  event UpdateHouseEdge(uint64 houseEdge);

  event Created(address indexed player, Game game);

  event Finishing(address indexed player, uint32 change);

  event Dealt(address indexed player, uint32 cards, uint256 wager, address token);

  event Finalized(
    address indexed player,
    uint256 payout,
    uint256 result,
    uint32 cards,
    uint256 wager,
    uint256 wagerWithMultiplier,
    address token
  );

  /*==================================================== State Variables ====================================================*/

  enum Status {
    IDLE,
    START,
    DEALT,
    FINALIZING
  }

  struct Game {
    Status status;
    address token;
    uint32 cards;
    uint32 change;
    uint64 startTime;
    uint128 wager;
    uint256 random;
  }

  struct DeckBuilder {
    uint256 random;
    uint deck;
  }

  /// @notice cooldown duration to refund
  uint32 public refundCooldown = 2 hours; // default value
  /// @notice house edge of game, used to calculate referrals share (200 = 2.00)
  uint64 public houseEdge = 200;
  /// @notice stores all games
  mapping(address => Game) public games;
  /// @notice random request id => player address pair
  mapping(uint64 => address) public requestPair;
  /// @notice multipliers of hands [JACKS_OR_BETTER, TWO_PAIR, THREE_OF_A_KIND, STRAIGHT, FLUSH, FULL_HOUSE, FOUR_OF_A_KIND, STRAIGHT_FLUSH, ROYAL_FLUSH]
  uint8[9] private payouts = [1, 2, 3, 5, 6, 8, 25, 50, 100];

  /*==================================================== Constant Variables ====================================================*/

  uint8 private constant STATE_AWAITING_RANDOMNESS_AT_START = 0;
  uint8 private constant STATE_STARTED = 1;
  uint8 private constant STATE_AWAITING_RANDOMNESS_AT_END = 2;
  uint8 private constant STATE_ENDED = 3;

  uint private constant MASK_CARD_0 = ~uint(63);
  uint private constant MASK_CARD_1 = ~uint(63 << 6);
  uint private constant MASK_CARD_2 = ~uint(63 << 12);
  uint private constant MASK_CARD_3 = ~uint(63 << 18);
  uint private constant MASK_CARD_4 = ~uint(63 << 24);

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) Core(_router) {}

  /// @notice the number is used to calculate referrals share
  /// @param _payouts test
  function updatePayouts(uint8[9] calldata _payouts) external onlyGovernance {
    for (uint8 i = 0; i < 9; ++i) {
      require(_payouts[i] >= 1, "Payout should be greater or equal than 1");
    }

    payouts = _payouts;

    emit UpdatePayouts(_payouts);
  }

  /// @notice function that calculation or return a constant of house edge
  /// @return payouts_ calculated house edge of game
  function getPayouts() public view returns (uint8[9] memory payouts_) {
    payouts_ = payouts;
  }

  /// @notice the number is used to calculate referrals share
  /// @param _houseEdge winning multipliplier
  function updateHouseEdge(uint64 _houseEdge) external onlyGovernance {
    houseEdge = _houseEdge;
    emit UpdateHouseEdge(_houseEdge);
  }

  /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge() public view returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /// @notice function to update refund block count
  /// @param _refundCooldown duration to refund
  function updateRefundCooldown(uint32 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  /// @notice function to refund uncompleted game wagers
  function refundGame(uint64 _requestId) external nonReentrant {
    uint64 requestId_ = _requestId;
    address player_ = requestPair[requestId_];
    Game memory game_ = games[player_];

    require(player_ == _msgSender(), "Only player");

    _refundGame(_requestId, player_, game_);
  }

  /// @notice function to refund uncompleted game wagers by team role
  function refundGameByTeam(uint64 _requestId) external nonReentrant onlyTeam {
    uint64 requestId_ = _requestId;
    address player_ = requestPair[requestId_];
    Game memory game_ = games[player_];

    require(player_ != address(0), "Game is not created");

    _refundGame(_requestId, player_, game_);
  }

  function _refundGame(uint64 _requestId, address player_, Game memory _game) internal {
    require(_game.status != Status.DEALT, "Already dealt");
    require(_game.status != Status.IDLE, "No game");
    require(_game.startTime + refundCooldown < block.timestamp, "Game is not refundable yet");

    vaultManager.refund(_game.token, _game.wager, 0, player_);

    delete games[player_];
    delete requestPair[_requestId];
  }

  /// @notice finds next card from the random number
  function nextCard(DeckBuilder memory builder) internal pure returns (uint) {
    do {
      uint card = builder.random & 63;

      // Create a mask with a single bit set at the card index
      uint mask = 1 << card;

      // Shift the random number right by 6 bits to discard the used card
      builder.random >>= 6;

      // Check whether the card has already been dealt
      if ((builder.deck & mask) == 0) {
        // Mark the card as dealt in the deck
        builder.deck |= mask;

        // Return the card index
        return card;
      }
    } while (builder.random > 0);

    // very low chance of happening
    revert("Invalid random number");
  }

  /// @notice dealts the cards at start
  function dealt(address _player, Game storage _game, uint256 _randomness) internal {
    // Create a new DeckBuilder struct with the provided random number and a fixed initial deck state
    DeckBuilder memory builder_ = DeckBuilder(_randomness, 16141147358858633216);

    // Generate five cards by calling the nextCard function and combining the results
    uint cards_ = nextCard(builder_) |
      (nextCard(builder_) << 6) |
      (nextCard(builder_) << 12) |
      (nextCard(builder_) << 18) |
      (nextCard(builder_) << 24);

    // Store the generated cards in the game state
    _game.cards = uint32(cards_);

    // Update the game status to indicate that the cards have been dealt
    _game.status = Status.DEALT;

    // Emit an event to notify interested parties about the card dealing
    emit Dealt(_player, _game.cards, _game.wager, _game.token);
  }

  /// @notice replaces the cards in order to player's choice
  /// @notice the choices made in bitwise to change first cards should send 10000 => 16
  function replace(Game storage _game, uint256 _randomness) internal {
    // Rebuild the deck from the current cards
    uint cards_ = _game.cards;
    // Calculate the deck with the selected cards marked as dealt
    uint deck_ = 16141147358858633216 | // Initialize deck with the initial state
      (1 << (cards_ & 63)) | // Mark the first card as dealt
      (1 << ((cards_ & 4032) >> 6)) | // Mark the second card as dealt
      (1 << ((cards_ & 258048) >> 12)) | // Mark the third card as dealt
      (1 << ((cards_ & 16515072) >> 18)) | // Mark the fourth card as dealt
      (1 << ((cards_ & 1056964608) >> 24)); // Mark the fifth card as dealt

    // Update the required cards
    uint change_ = _game.change;
    DeckBuilder memory builder_ = DeckBuilder(_randomness, deck_);

    // Check each bit in the change_ variable and replace the corresponding card if set
    if ((change_ & 1) != 0) {
      cards_ = (cards_ & MASK_CARD_0) | nextCard(builder_);
    }
    if ((change_ & 2) != 0) {
      cards_ = (cards_ & MASK_CARD_1) | (nextCard(builder_) << 6);
    }
    if ((change_ & 4) != 0) {
      cards_ = (cards_ & MASK_CARD_2) | (nextCard(builder_) << 12);
    }
    if ((change_ & 8) != 0) {
      cards_ = (cards_ & MASK_CARD_3) | (nextCard(builder_) << 18);
    }
    if ((change_ & 16) != 0) {
      cards_ = (cards_ & MASK_CARD_4) | (nextCard(builder_) << 24);
    }

    // Update the game state with the new set of cards
    _game.cards = uint32(cards_);
  }

  function finalize(address _player, Game storage _game) private {
    uint256 result_ = win(_game.cards);
    uint256 payout_;

    /// @notice sets referral reward if player has referee
    vaultManager.setReferralReward(_game.token, _player, _game.wager, getHouseEdge());
    uint256 wagerWithMultiplier_ = (_computeMultiplier((_game.random)) * _game.wager) / 1e3;
    vaultManager.mintVestedWINR(_game.token, wagerWithMultiplier_, _player);

    _hasLuckyStrike(_game.random, _player, _game.token, _game.wager);
    /// @notice calculates the loss of user if its not zero transfers to Vault
    if (result_ != 0) {
      payout_ = (payouts[result_ - 1] * _game.wager);
      vaultManager.payout(_game.token, _player, _game.wager, payout_);
    } else {
      vaultManager.payin(_game.token, _game.wager);
    }

    // event for frontend
    emit Finalized(_player, payout_, result_, _game.cards, _game.wager, wagerWithMultiplier_, _game.token);
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _requestId generated request id by randomizer
  /// @param _randoms raw random numbers sent by randomizers
  function randomizerFulfill(
    uint256 _requestId,
    uint256[] calldata _randoms
  ) internal override nonReentrant {
    uint64 requestId_ = uint64(_requestId);
    address player_ = requestPair[requestId_];
    Game storage game_ = games[player_];
    require(game_.status != Status.IDLE, "No game");

    game_.random = _randoms[0];
    if (game_.status == Status.START) {
      dealt(player_, game_, _randoms[0]);
      delete requestPair[requestId_];
    }

    if (game_.status == Status.FINALIZING) {
      replace(game_, _randoms[0]);
      finalize(player_, game_);

      delete games[player_];
      delete requestPair[requestId_];
    }
  }

  /// @notice starts the game and triggers randomizer
  /// @param _token input and output token
  /// @param _wager multiple game count
  function start(
    address _token,
    uint128 _wager
  ) external whenNotPaused nonReentrant isWagerAcceptable(_token, _wager) {
    address player_ = _msgSender();

    // checks whether player has already a game
    require(games[player_].wager == 0, "Only one game");

    // escrows total wager to Vault Manager
    vaultManager.escrow(_token, player_, _wager);

    // Creating game object
    games[player_] = Game(Status.START, _token, 0, 0, uint64(block.timestamp), _wager, 0);
    // keep request pair to find players game
    uint256 requestId_ = _requestRandom(1);
    require(requestId_ <= type(uint64).max, "Request id overflow");
    requestPair[uint64(requestId_)] = player_;

    emit Created(player_, games[player_]);
  }

  /// @notice finish request for the game and triggers randomizer
  /// @param _change the chards needs to be changed for first card, 10000 => 16
  function finish(uint32 _change) external whenNotPaused nonReentrant {
    address player_ = _msgSender();
    Game storage game_ = games[player_];
    require(game_.status == Status.DEALT, "Already finalized!");

    if (_change == 0) {
      finalize(player_, game_);
      delete games[player_];
      return;
    }
    uint256 requestId_ = _requestRandom(1);
    require(requestId_ <= type(uint64).max, "Request id overflow");
    requestPair[uint64(requestId_)] = player_;

    game_.change = _change;
    game_.status = Status.FINALIZING;
    game_.startTime = uint64(block.timestamp);

    emit Finishing(player_, _change);
  }
}
