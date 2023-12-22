// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Core.sol";

abstract contract CommonSoloKeno is Core {
  /*==================================================== Events =============================================================*/

  event Created(address indexed player, uint256 indexed requestId, uint256 wager, address token);

  event KenoResult(
    address indexed player,
    uint256 roundIndex,
    uint256 requestId,
    uint256[] resultNumbers
  );

  event GameRefunded(address indexed player, uint256 indexed requestId, uint256 totalRefunded);

  /**
   * @param player address of the player
   * @param requestId vrf request id of the game
   * @param wager amount of the wager PER GAME ROUND
   * @param won bool if the player won the game (net positive result if multiple rounds where played)
   * @param payout net payout amount to player (if any)
   * @param playedGameCount amount of game rounds played
   * @param payouts array of payouts for each game round
   */
  event Settled(
    address indexed player,
    uint256 requestId,
    address token,
    uint256 wager,
    bool won,
    uint256 payout,
    uint32 playedGameCount,
    uint256[] payouts
  );

  /*==================================================== State Variables ====================================================*/

  struct Game {
    uint8 count;
    uint128 wager;
    uint32 startTime;
    bool gameCompleted;
    uint32[] gameData;
    address player;
    address token;
  }

  struct GameDraws {
    uint32[10] firstDraw;
    uint32[10] secondDraw;
    uint32[10] thirdDraw;
  }

  struct Options {
    uint128 stopGain;
    uint128 stopLoss;
  }

  // maximum selectable game count
  uint256 public constant maxGameCount = 3;
  // cooldown duration to refund
  uint256 public refundCooldown = 2 hours; // default value
  // stores all games_
  mapping(uint256 => Game) internal games_;
  // stores randomizer request ids game pair
  mapping(uint256 => Options) internal options_;
  // mapping(uint256 => bool) public completedGames;
  mapping(uint256 => GameDraws) internal gameDraws_;

  constructor(IRandomizerRouter _router) Core(_router) {}

  function returnGameInfo(uint256 _requestId) external view returns (Game memory) {
    return games_[_requestId];
  }

  function returnOptionsInfo(uint256 _requestId) external view returns (Options memory) {
    return options_[_requestId];
  }

  function updateRefundCooldown(uint256 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  function getFirstDrawResult(uint256 _requestId) external view returns (uint32[10] memory) {
    return gameDraws_[_requestId].firstDraw;
  }

  function getSecondDrawResult(uint256 _requestId) external view returns (uint32[10] memory) {
    return gameDraws_[_requestId].secondDraw;
  }

  function getThirdDrawResult(uint256 _requestId) external view returns (uint32[10] memory) {
    return gameDraws_[_requestId].thirdDraw;
  }

  function getAllDrawResults(
    uint256 _requestId
  )
    external
    view
    returns (
      uint32[10] memory firstDraw_,
      uint32[10] memory secondDraw_,
      uint32[10] memory thirdDraw_
    )
  {
    firstDraw_ = gameDraws_[_requestId].firstDraw;
    secondDraw_ = gameDraws_[_requestId].secondDraw;
    thirdDraw_ = gameDraws_[_requestId].thirdDraw;
  }

  function shouldStop(
    uint256 _total,
    uint256 _wager,
    uint256 _stopGain,
    uint256 _stopLoss
  ) public pure returns (bool stop_) {
    if (_stopGain != 0 && _total > _wager) {
      stop_ = _total - _wager >= _stopGain; // total gain >= stop gain
    } else if (_stopLoss != 0 && _wager > _total) {
      stop_ = _wager - _total >= _stopLoss; // total loss >= stop loss
    }
  }

  function calcWager(
    uint256 _count,
    uint256 _usedCount,
    uint256 _wager
  ) internal pure returns (uint256 usedWager_, uint256 unusedWager_) {
    unchecked {
      // cannot underflow because _usedCount <= _count
      uint256 totalWager = _count * _wager;
      usedWager_ = _usedCount * _wager;
      unusedWager_ = totalWager - usedWager_;
    }
  }

  function refundGame(uint256 _requestId) external nonReentrant {
    Game memory game_ = games_[_requestId];
    require(game_.player == _msgSender(), "Only player");
    require(!game_.gameCompleted, "Keno: Game is completed - not refundable");
    require(game_.startTime + refundCooldown < block.timestamp, "Game is not refundable yet");
    _refundGame(_requestId);
  }

  function refundGameByTeam(uint256 _requestId) external nonReentrant onlyTeam {
    Game memory game_ = games_[_requestId];
    require(!game_.gameCompleted, "Keno: Game is completed - not refundable");
    require(game_.startTime + refundCooldown < block.timestamp, "Keno: Game is not refundable yet");
    _refundGame(_requestId);
  }

  function _refundGame(uint256 _requestId) internal {
    Game memory _game = games_[_requestId];
    uint256 totalRefund_ = _game.wager * _game.count;
    vaultManager.refund(_game.token, totalRefund_, 0, _game.player);
    games_[_requestId].gameCompleted = true;
    emit GameRefunded(_game.player, _requestId, totalRefund_);
  }

  function shareEscrow(
    Game memory _game,
    uint256 _playedGameCount,
    uint256 _payout
  ) internal virtual returns (bool) {
    (uint256 usedWager_, uint256 unusedWager_) = calcWager(
      _game.count,
      _playedGameCount,
      _game.wager
    );
    vaultManager.setReferralReward(_game.token, _game.player, usedWager_, getHouseEdge(_game));
    vaultManager.mintVestedWINR(_game.token, usedWager_, _game.player);

    if (unusedWager_ != 0) {
      vaultManager.payback(_game.token, _game.player, unusedWager_);
    }

    // calculates the loss of user if its not zero transfers to Vault
    if (_payout == 0) {
      vaultManager.payin(_game.token, usedWager_);
    } else {
      vaultManager.payout(_game.token, _game.player, usedWager_, _payout);
    }

    // The used wager is the zero point. if the payout is above the wager, player wins
    return _payout > usedWager_;
  }

  function getResultNumbers(uint256 _randoms) internal virtual returns (uint256[] memory numbers_);

  function getHouseEdge(Game memory _game) public view virtual returns (uint64 edge_);

  /**
   * @param _game Game struct with game info
   * @param _resultNumbers drawn random numbers by vrf
   * @param _stopGain stop gain (take profit) in token
   * @param _stopLoss stop loss amount in token
   * @return payout_ total payout amount in token
   * @return playedGameCount_ total amount of games_ played
   * @return payouts_ payout amount per round in token
   */
  function play(
    uint256 _requestId,
    Game memory _game,
    uint256[] memory _resultNumbers,
    uint128 _stopGain,
    uint128 _stopLoss
  ) internal virtual returns (uint256 payout_, uint256 playedGameCount_, uint256[] memory payouts_);

  function randomizerFulfill(
    uint256 _requestId,
    uint256[] calldata _randoms
  ) internal override nonReentrant {
    Game memory game_ = games_[_requestId];
    // this is an inverted whenNotCompleted(_requestId) flow - saves on gas
    require(!game_.gameCompleted, "Keno: Game is completed - not refundable");

    games_[_requestId].gameCompleted = true;

    require(game_.player != address(0), "Keno: Game is not created");
    Options memory options__ = options_[_requestId];
    (uint256 payout_, uint256 playedGameCount_, uint256[] memory payouts_) = play(
      _requestId,
      game_,
      _randoms,
      options__.stopGain,
      options__.stopLoss
    );

    emit Settled(
      game_.player,
      _requestId,
      game_.token,
      game_.wager,
      shareEscrow(game_, playedGameCount_, payout_),
      payout_,
      uint32(playedGameCount_),
      payouts_
    );
  }

  /**
   * @notice creates a new game
   * @param _wager amount bet in each game
   * @param _count max amount of games_
   * @param _stopGain take profit amount in token
   * @param _stopLoss stop loss amount in token
   * @param _gameData picked numbers for keno game
   * @param _token address of the token
   */
  function _create(
    uint128 _wager,
    uint8 _count,
    uint128 _stopGain,
    uint128 _stopLoss,
    uint32[] memory _gameData,
    address _token
  ) internal whenNotPaused nonReentrant {
    address player_ = _msgSender();

    // escrows total wager to Vault Manager
    vaultManager.escrow(_token, player_, _count * _wager);

    uint256 requestId_ = _requestRandom(_count);

    games_[requestId_] = Game(
      _count,
      _wager,
      uint32(block.timestamp),
      false,
      _gameData,
      player_,
      _token
    );

    if (_stopGain != 0 || _stopLoss != 0) {
      options_[requestId_] = Options(_stopGain, _stopLoss);
    }

    emit Created(player_, requestId_, _wager, _token);
  }
}

