// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Core.sol";

abstract contract CommonSoloBaccarat is Core {
  event Created(
    address indexed player,
    uint256 indexed requestId,
    uint256 totalWager,
    address token
  );

  event Settled(
    address indexed player,
    uint256 requestId,
    address token,
    uint256 wager,
    uint256 wagerWithMultiplier,
    bool won,
    uint256 payout
  );

  event HandFinalized(address indexed player, uint256 requestId, Hand playerHand, Hand bankerHand);

  event GameRefunded(address indexed player, uint256 indexed requestId, uint256 totalRefunded);

  struct BothHands {
    Hand playerHand;
    Hand bankerHand;
  }

  struct Hand {
    bool hasThirdCard;
    uint8 firstCard;
    uint8 secondCard;
    uint8 thirdCard;
  }

  struct Bet {
    bool gameCompleted;
    uint144 tokenPrice;
    uint24 totalWagerInChips;
    uint24 tieWinsInChips;
    uint24 bankWinsInChips;
    uint24 playerWinsInChips;
    uint8 decimals;
  }

  struct BaccaratGame {
    address player;
    address token;
    uint32 startTime;
    Bet bet;
    Hand playerHand;
    Hand bankerHand;
  }

  uint32 public refundCooldown = 2 hours; // default value

  mapping(uint256 => BaccaratGame) internal games_;

  // mapping(address => uint256) private decimalsOfToken;

  // minWagerAmount 1$
  uint256 public constant minWagerAmount = 1e17;

  constructor(IRandomizerRouter _router) Core(_router) {}

  function updateRefundCooldown(uint32 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  function games(uint256 _requestId) external view returns (BaccaratGame memory) {
    return games_[_requestId];
  }

  function refundGame(uint256 _requestId) external nonReentrant {
    BaccaratGame memory game_ = games_[_requestId];
    require(game_.player == _msgSender(), "Baccarat: Only player can request refund");
    require(!game_.bet.gameCompleted, "Baccarat: Game is completed - not refundable");
    require(
      game_.startTime + refundCooldown < block.timestamp,
      "Baccarat: Game is not refundable yet"
    );
    _refundGame(_requestId);
  }

  function refundGameByTeam(uint256 _requestId) external nonReentrant onlyTeam {
    BaccaratGame memory game_ = games_[_requestId];
    require(!game_.bet.gameCompleted, "Baccarat: Game is completed - not refundable");
    require(
      game_.startTime + refundCooldown < block.timestamp,
      "Baccarat: Game is not refundable yet"
    );
    _refundGame(_requestId);
  }

  function _refundGame(uint256 _requestId) internal {
    BaccaratGame memory _game = games_[_requestId];

    games_[_requestId].bet.gameCompleted = true;

    (uint256 _tokenAmount, ) = _chip2Token(
      _game.bet.totalWagerInChips,
      _game.token,
      _game.bet.tokenPrice
    );

    vaultManager.refund(_game.token, _tokenAmount, 0, _game.player);

    emit GameRefunded(_game.player, _requestId, _tokenAmount);
  }

  function shareEscrow(
    BaccaratGame memory _game,
    uint256 _payoutInTokens,
    uint256 _random
  ) internal virtual returns (bool hasWon_, uint256 totalWager_, uint256) {
    (totalWager_, ) = _chip2Token(_game.bet.totalWagerInChips, _game.token, _game.bet.tokenPrice);

    vaultManager.setReferralReward(_game.token, _game.player, totalWager_, getHouseEdge());

    uint256 wagerWithMultiplier_ = (_computeMultiplier(_random) * totalWager_) / 1e3;
    vaultManager.mintVestedWINR(_game.token, wagerWithMultiplier_, _game.player);

    _hasLuckyStrike(_random, _game.player, _game.token, totalWager_);

    /// @notice calculates the loss of user if its not zero transfers to Vault
    if (_payoutInTokens == 0) {
      vaultManager.payin(_game.token, totalWager_);
    } else {
      vaultManager.payout(_game.token, _game.player, totalWager_, _payoutInTokens);
    }

    /// @notice The used wager is the zero point. if the payout is above the wager, player wins
    hasWon_ = _payoutInTokens > totalWager_;

    return (hasWon_, totalWager_, wagerWithMultiplier_);
  }

  // function that returns the game data struct
  function getGameData(uint256 _requestId) external view returns (BaccaratGame memory) {
    return games_[_requestId];
  }

  function getBankerHand(uint256 _requestId) external view returns (Hand memory) {
    return games_[_requestId].bankerHand;
  }

  function getPlayerHand(uint256 _requestId) external view returns (Hand memory) {
    return games_[_requestId].playerHand;
  }

  function getResultNumbers(
    uint256 _randoms
  ) internal virtual returns (uint256[6] memory topCards_);

  function getHouseEdge() public view virtual returns (uint64 edge_);

  /**
   * @notice returns the amount of tokens and the dollar value of a certain amount of chips in a game
   * @param _chips amount of chips
   * @param _token token address
   * @param _price usd price of the token (scaled 1e30)
   * @return tokenAmount_ amount of tokens that the chips are worth
   * @return dollarValue_ dollar value of the chips
   */
  function _chip2Token(
    uint256 _chips,
    address _token,
    uint256 _price
  ) internal returns (uint256 tokenAmount_, uint256 dollarValue_) {
    uint256 decimals_ = _getDecimals(_token);
    unchecked {
      tokenAmount_ = ((_chips * (10 ** (30 + decimals_)))) / _price;
      dollarValue_ = (tokenAmount_ * _price) / (10 ** decimals_);
    }
    return (tokenAmount_, dollarValue_);
  }

  /**
   *
   * @param _chips amount of chips
   * @param _decimals decimals of token
   * @param _price price of token (scaled 1e30)
   */
  function _chip2TokenDecimals(
    uint256 _chips,
    uint256 _decimals,
    uint256 _price
  ) internal pure returns (uint256 tokenAmount_) {
    unchecked {
      tokenAmount_ = ((_chips * (10 ** (30 + _decimals)))) / _price;
    }
    return tokenAmount_;
  }

  function play(
    uint256 _requestId,
    Bet memory _bet,
    uint256 _random
  ) internal virtual returns (uint256 payout_);

  function randomizerFulfill(
    uint256 _requestId,
    uint256[] calldata _randoms
  ) internal override nonReentrant {
    BaccaratGame memory game_ = games_[_requestId];
    require(game_.player != address(0), "Baccarat: Game is not created");

    require(!game_.bet.gameCompleted, "Baccarat: Game is completed");

    games_[_requestId].bet.gameCompleted = true;

    uint256 payout_ = play(_requestId, game_.bet, _randoms[0]);

    (bool hasWon_, uint256 totalWager_, uint256 wagerWithMultiplier_) = shareEscrow(
      game_,
      payout_,
      _randoms[0]
    );

    emit Settled(
      game_.player,
      _requestId,
      game_.token,
      totalWager_,
      wagerWithMultiplier_,
      hasWon_,
      payout_
    );
  }

  function _create(
    Bet memory _betInfo,
    uint256 _wagerAmount,
    address _token
  ) internal whenNotPaused nonReentrant {
    address player_ = _msgSender();

    vaultManager.escrow(_token, player_, _wagerAmount);

    uint256 requestId_ = _requestRandom(1);

    games_[requestId_] = BaccaratGame(
      player_,
      _token,
      uint32(block.timestamp),
      _betInfo,
      Hand(false, 0, 0, 0),
      Hand(false, 0, 0, 0)
    );

    emit Created(player_, requestId_, _wagerAmount, _token);
  }
}

