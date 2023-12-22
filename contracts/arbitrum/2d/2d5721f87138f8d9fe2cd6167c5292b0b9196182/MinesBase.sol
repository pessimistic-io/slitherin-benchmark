// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Core.sol";

abstract contract MinesBase is Core {
  /*==================================================== Events =============================================================*/
   /**
     * @dev event emitted by the randomizer fulfill with the cell reveal results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout payout if player were to end the game
     * @param token address of token the wager was made and payout
     * @param minesCells cells in which mines were revealed, if any is true the game is over and the player lost
     * @param revealedCells all cells that have been revealed, true correspond to a revealed cell
     * @param multiplier current game multiplier if the game player chooses to end the game
     */
    event Reveal(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address token,
        bool[25] minesCells,
        bool[25] revealedCells,
        uint256 multiplier
    );

    /**
     * @dev event emitted by the randomizer fulfill with the cell reveal results and cashout
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param token address of token the wager was made and payout
     * @param minesCells cells in which mines were revealed, if any is true the game is over and the player lost
     * @param revealedCells all cells that have been revealed, true correspond to a revealed cell
     * @param multiplier current game multiplier
     */
    event RevealAndCashout(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address token,
        bool[25] minesCells,
        bool[25] revealedCells,
        uint256 multiplier
    );

    /**
     * @dev event emitted by the randomizer fulfill with the bet results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param token address of token the wager was made and payout
     * @param multiplier final game multiplier
     */
    event Settled(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address token,
        uint256 multiplier
    );

    /**
     * @dev event emitted when a player makes a bet
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param token address of token the wager was made and payout
     * @param requestId random number request id of the bet
     * @param numMines number of mines in the game
     */
    event Created(
        address indexed playerAddress,
        uint256 wager,
        address token,
        uint256 requestId,
        uint8 numMines
    );


  /*==================================================== State Variables ====================================================*/

    struct Game {
        address player;
        address token;
        uint256 wager;
        uint256 requestId;
        uint256 startTime;
        uint64 currentMultiplier;
        uint8 numMines;
        bool[25] revealedCells;
        bool[25] cellsPicked;
        bool isCashout;
    }

  /// @notice house edge of game
  uint64 public houseEdge = 200; // 2%
  /// @notice cooldown duration to refund
  uint32 public refundCooldown = 2 hours; // default value

  uint32 public endByTeamCooldown = 2 hours; // default value
  /// @notice stores all games
  mapping(address => Game) public games;
  /// @notice stores all game ids
  mapping(uint256 => address) public gameIds;

  mapping(uint256 => mapping(uint256 => uint256)) minesMultipliers;
  mapping(uint8 => uint256) minesMaxReveal;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) Core(_router) {}

    /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory) public view returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /// @notice function to update refund block count
  /// @param _refundCooldown duration to refund
  function updateRefundCooldown(uint32 _refundCooldown) external onlyGovernance {
    refundCooldown = _refundCooldown;
  }

  /// @notice function to update end game by team block count
  /// @param _endByTeamCooldown duration to end game by team
  function updateEndByTeamCooldown(uint32 _endByTeamCooldown) external onlyGovernance {
    require(_endByTeamCooldown >= refundCooldown, "Mines: End by team cooldown must be greater than refund cooldown");
    endByTeamCooldown = _endByTeamCooldown;
  }


  /// @notice function to refund uncompleted game wagers
  function refundGame() external nonReentrant{
    address player_ = _msgSender();
    Game memory game = games[player_];
    require(game.player == player_, "Mines: Only player");
    require(game.startTime + refundCooldown < block.timestamp, "Mines: Game is not refundable yet");
    _refundGame(player_);
  }

  /// @notice function to refund uncompleted game wagers by team role
  function refundGameByTeam(
    address _player
  ) external nonReentrant onlyTeam {
    Game memory game = games[_player];
    require(game.startTime + refundCooldown < block.timestamp, "Mines: Game is not refundable yet");
    _refundGame(_player);
  }

  function _refundGame(address _player) internal {
    Game memory _game = games[_player];
    require(_game.currentMultiplier == 0, "Mines: Game is only refundable if it has not passed the first round");
    vaultManager.refund(_game.token, _game.wager, 0, _player);

    delete gameIds[_game.requestId];
    delete games[_player];
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _game player's game
  /// @param _wager wager of the game
  /// @param _payout accumulated payouts by game contract
  function shareEscrow(
    Game memory _game,
    uint256 _wager,
    uint256 _payout
  ) internal virtual returns (bool) {

    /// @notice sets referral reward if player has referee
    vaultManager.setReferralReward(_game.token, _game.player, _wager, getHouseEdge(_game));
    vaultManager.mintVestedWINR(_game.token, _wager, _game.player);
  
    /// @notice calculates the loss of user if its not zero transfers to Vault
    if (_payout == 0) {
      vaultManager.payin(_game.token, _wager);
    } else {
      vaultManager.payout(_game.token, _game.player, _wager, _payout);
    }

    /// @notice The used wager is the zero point. if the payout is above the wager, player wins
    return _payout > _wager;
  }



  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _wager amount for a game
  /// @param _token input and output token
  function _create( uint8 _numMines, uint256 _wager, address _token, bool _isCashout, bool[25] memory _cells
  
  )
    internal
    isWagerAcceptable(_token, _wager)
    whenNotPaused
    returns(uint256)
  {
    address player_ = _msgSender();
    uint256 requestId_ = _requestRandom(1);
    /// @notice escrows total wager to Vault Manager
    vaultManager.escrow(_token, player_, _wager);

    Game storage game = games[player_];

    game.player = player_;
    game.token = _token;
    game.wager = _wager;
    game.requestId = requestId_;
    game.startTime = block.timestamp;
    game.numMines = _numMines;
    game.cellsPicked = _cells;
    game.isCashout = _isCashout;

    gameIds[requestId_] = player_;
    return requestId_;
   
  }
}

