// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Core.sol";

contract HorseRace is Core {
  /*==================================================== Events =============================================================*/

  event Created(uint256 indexed gameId, uint256 startTime);

  event Participated(
    uint256 indexed gameId,
    address player,
    uint256 amount,
    uint256 mintedVWINR,
    uint8 horse,
    address token
  );

  event Claimed(address indexed player, uint256 gameId);

  event ClaimedBatch(uint256 indexed gameId, address[] players);

  event Settled(uint256 indexed gameId, uint8 horse, uint64 multiplier);

  event UpdateHouseEdge(uint64 houseEdge);

  /*==================================================== State Variables ====================================================*/

  enum Status {
    IDLE,
    STARTED,
    RACE,
    FINISHED,
    REFUNDED
  }

  struct Configuration {
    uint16 duration;
    uint16 cooldown;
    uint16[5] horseProbabilities;
  }

  struct Bet {
    uint8 horse;
    uint256 amount;
    address token;
    uint256 referralReward;
    uint256 mintedVWINR;
  }

  struct Game {
    uint8 horse;
    Status status;
    uint256 startTime;
  }

  /// @notice house edge of game
  uint64 public houseEdge = 200;
  uint64 public startTime;
  /// @notice game ids
  uint256 public currentGameId = 0;
  /// @notice block count to refund
  uint32 public refundCooldown = 2 hours; // default value
  /// @notice game list
  mapping(uint256 => Game) public games;
  /// @notice holds total wager amounts according to currency and choice
  mapping(bytes => uint256) public amounts;
  /// @notice bet refunds
  mapping(uint256 => mapping(address => bool)) public refunds;
  /// @notice game player claim pair
  mapping(uint256 => mapping(address => bool)) public claims;
  /// @notice participant list of game
  mapping(uint256 => mapping(address => Bet)) public participants;
  /// @notice holds total wager amounts according to currency
  mapping(uint256 => mapping(address => uint256)) public totalAmounts;
  /// @notice wagering duration 20s, cooldown duration after wagering closed 30s
  /// @notice horse probabilities 0.48, 0.32, 0.12, 0.064, 0.016 scaled by 10000
  Configuration public config = Configuration(20, 30, [4800, 3200, 1200, 640, 160]);
  /// @notice horse's multiplier pair
  mapping(uint8 => uint64) public multipliers;
  /// @notice randomizer request id and game id pair to find the game related with request
  mapping(uint256 => uint256) public requestGamePair;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _randomizerRouter) Core(_randomizerRouter) {
    // Default Multipliers
    multipliers[1] = 200; // 2x
    multipliers[2] = 300; // 3x
    multipliers[3] = 800; // 8x
    multipliers[4] = 1500; // 15x
    multipliers[5] = 6000; // 60x

  }

  /// @notice function to update refund block count
  /// @param _refundCooldown block count to refund
  function updateRefundCooldown(uint32 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  /// @notice updates multiplier of horse
  /// @param _horse horse id
  /// @param _multiplier winning multiplier of horse
  function updateHorseMultiplier(uint8 _horse, uint64 _multiplier) public onlyGovernance {
    multipliers[_horse] = _multiplier;
  }

  /// @notice updates configurations of the game
  /// @param _config Configuration
  function updateConfigAndUnits(
    Configuration calldata _config
  ) external onlyGovernance whenPaused {
    require(_config.horseProbabilities.length == 5, "HR: horse probabilities length is not 5");
    config = _config;

  }

  /// @notice function that calculation or return a constant of house edge
  /// @param _houseEdge edge percent of game eg. 1000 = 10.00
  function updateHouseEdge(uint64 _houseEdge) external onlyGovernance {
    houseEdge = _houseEdge;

    emit UpdateHouseEdge(_houseEdge);
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _wager players wager for a game
  /// @param _horse chosen horse by player
  function calcReward(uint256 _wager, uint8 _horse) public view returns (uint256 reward_) {
    reward_ = (_wager * multipliers[_horse]) / 1e2;
  }

  /// @param _random raw random number
  function getWinningHorse(uint256 _random) public view returns (uint8 winningHorse_) {
    _random = _random % 10000;
    uint16[5] memory horseProbabilities_ = config.horseProbabilities;
   if (_random < horseProbabilities_[0]) {
            winningHorse_ = 1;
        } else if (_random < (horseProbabilities_[0] + horseProbabilities_[1])) {
            winningHorse_ = 2;
        } else if (_random < (horseProbabilities_[0] + horseProbabilities_[1] + horseProbabilities_[2])) {
            winningHorse_ = 3;
        } else if (_random < (horseProbabilities_[0] + horseProbabilities_[1] + horseProbabilities_[2] + horseProbabilities_[3])) {
            winningHorse_ = 4;
        } else {
            winningHorse_ = 5;
        }
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _gameId played game id
  /// @param _token address of input
  /// @param _horse choice
  function generateCurrencyId(
    uint256 _gameId,
    address _token,
    uint8 _horse
  ) internal pure returns (bytes memory id_) {
    id_ = abi.encode(_gameId, _token, _horse);
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _requestId generated request id by randomizer
  /// @param _randoms raw random numbers sent by randomizers
  function randomizerFulfill(uint256 _requestId, uint256[] calldata _randoms) internal override {
    /// @notice checks whether the game is finished
    uint256 gameId_ = requestGamePair[_requestId];

    Game storage game_ = games[gameId_];
    require(block.timestamp > games[gameId_].startTime + config.duration, "HR: Must after game finished");
  
    require(
      block.timestamp < games[gameId_].startTime + refundCooldown,
      "HR: FulFill is not allowed after the refund cooldown"
    );

    require(game_.status == Status.STARTED, "HR: Game can not fulfill");

    /// @notice finds the winning horse
    (uint8 winningHorse_) = getWinningHorse(_randoms[0]);
    IVaultManager vaultManager_ = vaultManager;

    /// @notice gets currencies which are used to escrow wager
    address[] memory currencies = vaultManager_.getWhitelistedTokens();

    bytes memory currencyId;
    address token_;
    uint256 amount_;
    uint256 totalAmount_;

    /// @notice decreases winning amounts from total amounts
    /// @notice and transfers the amounts to vault
    for (uint8 i = 0; i < currencies.length; ++i) {
      token_ = currencies[i];
      currencyId = generateCurrencyId(gameId_, token_, winningHorse_);
      amount_ = amounts[currencyId];
      totalAmount_ = totalAmounts[gameId_][token_];

      if (totalAmount_ > amount_) {
        vaultManager.payin(token_, totalAmount_ - amount_);
        totalAmounts[gameId_][token_] = amount_;
      }
    }

    /// @notice closes the game
    game_.horse = winningHorse_;
    game_.status = Status.FINISHED;

    emit Settled(gameId_, winningHorse_, multipliers[winningHorse_]);
  }

  /// @notice creates new game if the previous has timed out
  function _createGame() internal {
    uint256 currentGameId_ = currentGameId;
    uint256 finishTime_ = games[currentGameId_].startTime + config.duration + config.cooldown;
    uint256 startTime_ = block.timestamp;

    /// @notice if the last game has finished
    if (startTime_ > finishTime_) {
      currentGameId_++;

      /// @notice schedules random request for game for after wagering duration
     uint256 requestId_ = _requestScheduledRandom(1, startTime_ + config.duration + config.cooldown);

      requestGamePair[requestId_] = currentGameId_;

      games[currentGameId_] = Game(0, Status.STARTED, startTime_);

      emit Created(currentGameId_, startTime_);

      currentGameId = currentGameId_;
    }
  }

  /// @notice gets current game
  function getCurrentGame() external view returns (Game memory) {
    Game memory game_ = games[currentGameId];
    uint256 raceStartTime;

    unchecked {
      raceStartTime = game_.startTime + config.duration;
    }

    /// @notice if wagering time is finished, horses should race
    if (block.timestamp >= raceStartTime && game_.status == Status.STARTED) {
      game_.status = Status.RACE;
    }

    return game_;
  }

  /// @notice escrows tokens and writes the amounts
  /// @param _player address of player
  /// @param _wager amount for a game
  /// @param _horse selected horse by player
  /// @param _token wager token address
  function _escrow(
    address _player,
    uint256 _wager,
    uint8 _horse,
    address _token
  ) internal returns (uint256 referralReward_, uint256 vWINRAmount_) {
    IVaultManager vaultManager_ = vaultManager;
    bytes memory currencyId = generateCurrencyId(currentGameId, _token, _horse);

    unchecked {
      totalAmounts[currentGameId][_token] += _wager;
      amounts[currencyId] += _wager;
    }

    /// @notice escrows total wager to Vault Manager
    vaultManager_.escrow(_token, _player, _wager);

    /// @notice mints the vWINR rewards
    vWINRAmount_ = vaultManager_.mintVestedWINR(_token, _wager, _player);
    /// @notice sets referral reward if player has referee
    referralReward_ = vaultManager_.setReferralReward(_token, _player, _wager, houseEdge);
  }


  /// @notice makes bet for current game or creates if previous one is finished
  /// @param _wager amount for a game
  /// @param _horse selected horse by player
  /// @param _token which token will be used for a game
  function bet(
    uint256 _wager,
    uint8 _horse,
    address _token
  ) external nonReentrant isWagerAcceptable(_token, _wager) whenNotPaused {
    _createGame();
    uint256 raceStartTime = games[currentGameId].startTime + config.duration;
    require(block.timestamp < raceStartTime, "HR: Game closed");
    require(_horse != 0, "Choose a horse");
    require(_horse <= config.horseProbabilities.length, "Invalid horse number");

    address player_ = _msgSender();
    uint256 currentGameId_ = currentGameId;
    require(participants[currentGameId_][player_].amount == 0, "Bet cannot change");

    (uint256 _referralReward, uint256 _vWINRAmount) = _escrow(player_, _wager, _horse, _token);

    /// @notice sets players bet to the list
    participants[currentGameId_][player_] = Bet(
      _horse,
      _wager,
      _token,
      _referralReward,
      _vWINRAmount
    );

    emit Participated(currentGameId_, player_, _wager, _vWINRAmount, _horse, _token);
  }

  function refundGame(uint256 _gameId) external nonReentrant whenNotPaused {
    address player_ = _msgSender();
    _refundGame(player_, _gameId);
  }

  function refundGameByTeam(uint256 _gameId, address _player) external nonReentrant onlyTeam {
    _refundGame(_player, _gameId);
  }

  function _refundGame(address _player, uint256 _gameId) internal {
    Bet storage bet_ = participants[_gameId][_player];
    Game storage game_ = games[_gameId];

    if (game_.status != Status.REFUNDED) {
      require(
        game_.startTime + refundCooldown < block.timestamp,
        "HR: Game is not refundable yet"
      );
      require(game_.status == Status.STARTED, "HR: Game can not refund");
      game_.status = Status.REFUNDED;
    }
    require(bet_.amount != 0, "HR: Cant refund zero");

    uint256 _amount = bet_.amount;
    bet_.amount = 0;
    refunds[_gameId][_player] = true;

    vaultManager.refund(bet_.token, _amount, bet_.mintedVWINR, _player);
    vaultManager.removeReferralReward(bet_.token, _player, bet_.referralReward, BASIS_POINTS);
  }

  /// @notice transfer players winning
  /// @param _player amount for a game
  /// @param _bet contains input and output token currencies
  function _claim(address _player, Bet memory _bet) internal {
    vaultManager.payout(_bet.token, _player, _bet.amount, calcReward(_bet.amount, _bet.horse));
  }

  /// @notice Called by player to claim profits of a game
  /// @param _gameId game id which wants to be claimed
  function claim(uint256 _gameId) external nonReentrant {
    address sender_ = _msgSender();
    Game memory game_ = games[_gameId];
    Bet memory bet_ = participants[_gameId][sender_];

    require(!claims[_gameId][sender_], "HR: Already claimed");
    require(game_.status == Status.FINISHED, "HR: Game hasn't finished yet");
    require(bet_.horse == game_.horse, "HR: Lost");

    claims[_gameId][sender_] = true;
    _claim(sender_, bet_);

    emit Claimed(sender_, _gameId);
  }

  /// @notice Called by nodes to send profits of players
  /// @param _gameId game id which wants to be claimed
  /// @param _players game id which wants to be claimed
  function claimBatch(uint256 _gameId, address[] memory _players) external nonReentrant {
    Game memory game_ = games[_gameId];
    require(game_.status == Status.FINISHED, "HR: Game is not finished");
    for (uint256 i = 0; i < _players.length; i++) {
      address player_ = _players[i];
      Bet memory bet_ = participants[_gameId][player_];
      
      if (game_.horse == bet_.horse && !claims[_gameId][player_]) {
        claims[_gameId][player_] = true;
        _claim(player_, bet_);
      }
    }

    emit ClaimedBatch(_gameId, _players);
  }
}
