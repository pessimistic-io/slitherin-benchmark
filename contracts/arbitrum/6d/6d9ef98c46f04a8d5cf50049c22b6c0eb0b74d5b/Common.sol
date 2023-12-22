// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Core.sol";

abstract contract CommonSolo is Core {
  /*==================================================== Events =============================================================*/

  event Created(address indexed player, uint256 requestId, uint256 wager, address token);

  event Settled(
    address indexed player,
    uint256 requestId,
    uint256 wager,
    uint256 wagerWithMultiplier,
    bool won,
    uint256 payout,
    uint32 playedGameCount,
    uint256[] numbers,
    uint256[] payouts
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isGameCountAcceptable(uint256 _gameCount) {
    require(_gameCount > 0, "Game count out-range");
    require(_gameCount <= maxGameCount, "Game count out-range");
    _;
  }

  modifier isGameCreated(uint256 _requestId) {
    require(games[_requestId].player != address(0), "Game is not created");
    _;
  }

  modifier whenNotCompleted(uint256 _requestId) {
    require(!completedGames[_requestId], "Game is completed");
    completedGames[_requestId] = true;
    _;
  }

  /*==================================================== State Variables ====================================================*/

  // // better game struct
  struct Game {
    uint8 count;
    uint128 wager;
    uint32 startTime;
    bytes gameData;
    address player;
    address token;
  }

  struct Options {
    uint128 stopGain;
    uint128 stopLoss;
  }

  /// @notice maximum selectable game count
  uint8 public maxGameCount = 100;
  /// @notice cooldown duration to refund
  uint32 public refundCooldown = 2 hours; // default value
  /// @notice stores all games
  mapping(uint256 => Game) public games;
  /// @notice stores randomizer request ids game pair
  mapping(uint256 => Options) public options;
  mapping(uint256 => bool) public completedGames;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) Core(_router) {}

  /// @notice updates max game count
  /// @param _maxGameCount maximum selectable count
  function updateMaxGameCount(uint8 _maxGameCount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    maxGameCount = _maxGameCount;
  }

  /// @notice function to update refund block count
  /// @param _refundCooldown duration to refund
  function updateRefundCooldown(uint32 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  /// @notice checks the profit and loss amount to stop the game when reaches the limits
  /// @param _total total gain accumulated from all games
  /// @param _wager total wager used
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  function shouldStop(
    uint256 _total,
    uint256 _wager,
    uint256 _stopGain,
    uint256 _stopLoss
  ) public pure returns (bool stop_) {
    unchecked {
      if (_stopGain != 0 && _total > _wager) {
        stop_ = _total - _wager >= _stopGain; // total gain >= stop gain
      } else if (_stopLoss != 0 && _wager > _total) {
        stop_ = _wager - _total >= _stopLoss; // total loss >= stop loss
      }
    }
  }

  /// @notice if the game is stopped due to the win and loss limit,
  /// @notice this calculates the unused and used bet amount
  /// @param _count the selected game count by player
  /// @param _usedCount played game count by game contract
  /// @param _wager amount for a game
  function calcWager(
    uint256 _count,
    uint256 _usedCount,
    uint256 _wager
  ) public pure returns (uint256 usedWager_, uint256 unusedWager_) {
    unchecked {
      usedWager_ = _usedCount * _wager;
      unusedWager_ = (_count * _wager) - usedWager_;
    }
  }

  /// @notice function to refund uncompleted game wagers
  function refundGame(uint256 _requestId) external nonReentrant whenNotCompleted(_requestId) {
    Game memory game = games[_requestId];
    require(game.player == _msgSender(), "Only player");
    require(game.startTime + refundCooldown < block.timestamp, "Game is not refundable yet");
    _refundGame(_requestId);
  }

  /// @notice function to refund uncompleted game wagers by team role
  function refundGameByTeam(
    uint256 _requestId
  ) external nonReentrant onlyTeam whenNotCompleted(_requestId) {
    Game memory game = games[_requestId];
    require(game.startTime + refundCooldown < block.timestamp, "Game is not refundable yet");
    _refundGame(_requestId);
  }

  function _refundGame(uint256 _requestId) internal {
    Game memory _game = games[_requestId];

    vaultManager.refund(_game.token, _game.wager * _game.count, 0, _game.player);
    delete games[_requestId];
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _game player's game
  /// @param _playedGameCount played game count by game contract
  /// @param _payout accumulated payouts by game contract
  function shareEscrow(
    Game memory _game,
    uint256 _playedGameCount,
    uint256 _payout,
    uint256 _rnd
  ) internal virtual returns (bool, uint256) {
    (uint256 usedWager_, uint256 unusedWager_) = calcWager(
      _game.count,
      _playedGameCount,
      _game.wager
    );
    /// @notice sets referral reward if player has referee
    vaultManager.setReferralReward(_game.token, _game.player, usedWager_, getHouseEdge(_game));

    uint256 wagerWithMultiplier_ = (_computeMultiplier((_rnd)) * usedWager_) / 1e3;
    vaultManager.mintVestedWINR(_game.token, wagerWithMultiplier_, _game.player);
    _hasLuckyStrike(_rnd, _game.player, _game.token, usedWager_);

    /// @notice this call transfers the unused wager to player
    if (unusedWager_ != 0) {
      vaultManager.payback(_game.token, _game.player, unusedWager_);
    }

    /// @notice calculates the loss of user if its not zero transfers to Vault
    if (_payout == 0) {
      vaultManager.payin(_game.token, usedWager_);
    } else {
      vaultManager.payout(_game.token, _game.player, usedWager_, _payout);
    }

    /// @notice The used wager is the zero point. if the payout is above the wager, player wins
    return (_payout > usedWager_, wagerWithMultiplier_);
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _game request's game
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory _game,
    uint256[] calldata _randoms
  ) internal virtual returns (uint256[] memory numbers_);

  /// @notice function that calculation or return a constant of house edge
  /// @param _game request's game
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory _game) public view virtual returns (uint64 edge_);

  /**
   * @dev game logic contains here, decision mechanism
   * @param _game request's game
   * @param _resultNumbers modded numbers according to game
   * @param _stopGain maximum profit limit
   * @param _stopLoss maximum loss limit
   * @return payout_ _payout accumulated payouts by game contract
   * @return playedGameCount_  played game count by game contract
   * @return payouts_ profit calculated at every step of the game, wager excluded
   */
  function play(
    Game memory _game,
    uint256[] memory _resultNumbers,
    uint256 _stopGain,
    uint256 _stopLoss
  )
    public
    view
    virtual
    returns (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_);

  /**
   * @dev randomizer consumer triggers that function
   * @dev manages the game variables and shares the escrowed amount
   * @param _requestId generated request id by randomizer
   * @param _randoms raw random numbers sent by randomizers
   */
  function randomizerFulfill(
    uint256 _requestId,
    uint256[] calldata _randoms
  ) internal override isGameCreated(_requestId) whenNotCompleted(_requestId) nonReentrant {
    Game memory game_ = games[_requestId];
    uint256[] memory resultNumbers_ = getResultNumbers(game_, _randoms);
    Options memory options_ = options[_requestId];
    (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_) = play(
      game_,
      resultNumbers_,
      options_.stopGain,
      options_.stopLoss
    );

    uint256 randomForMultiplier_ = _randoms[0];
    (bool isWin_, uint256 wagerWithMultiplier_) = shareEscrow(
      game_,
      playedGameCount_,
      payout_,
      randomForMultiplier_
    );

    emit Settled(
      game_.player,
      _requestId,
      game_.wager,
      wagerWithMultiplier_,
      isWin_,
      payout_,
      playedGameCount_,
      resultNumbers_,
      payouts_
    );

    // clear storage
    delete games[_requestId];
    delete options[_requestId];
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _wager amount for a game
  /// @param _count the selected game count by player
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @param _gameData players decisions according to game
  /// @param _token input and output token
  function _create(
    uint256 _wager,
    uint8 _count,
    uint256 _stopGain,
    uint256 _stopLoss,
    bytes memory _gameData,
    address _token
  )
    internal
    isGameCountAcceptable(_count)
    isWagerAcceptable(_token, _wager)
    whenNotPaused
    nonReentrant
  {
    address player_ = _msgSender();
    uint256 requestId_ = _requestRandom(_count);

    /// @notice escrows total wager to Vault Manager
    vaultManager.escrow(_token, player_, _count * _wager);

    games[requestId_] = Game(
      _count,
      uint128(_wager),
      uint32(block.timestamp),
      _gameData,
      player_,
      _token
    );

    if (_stopGain != 0 || _stopLoss != 0) {
      options[requestId_] = Options(uint128(_stopGain), uint128(_stopLoss));
    }

    emit Created(player_, requestId_, _wager, _token);
  }
}

