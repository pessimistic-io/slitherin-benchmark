// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./MinesBase.sol";

contract Mines is MinesBase {
  constructor(IRandomizerRouter _router) MinesBase(_router) {}

  /**
   * @dev function to set game multipliers only callable by the governance
   * @dev computes the multipliers with 2% house edge
   * @param _numMines number of mines to set multipliers for
   */
  function setMultipliers(uint256 _numMines) external onlyGovernance {
    for (uint256 g = 1; g <= 25 - _numMines; g++) {
      uint256 multiplier = 1;
      uint256 divisor = 1;
      for (uint256 f = 0; f < g; f++) {
        multiplier *= (25 - _numMines - f);
        divisor *= (25 - f);
      }
      minesMultipliers[_numMines][g] = (9800 * (10 ** 9)) / ((multiplier * (10 ** 9)) / divisor);
    }
  }

  /**
   * @dev function to view the current mines multipliers
   * @param _numMines number of mines in the game
   * @param _numRevealed cells revealed
   */
  function getMultipliers(
    uint256 _numMines,
    uint256 _numRevealed
  ) public view returns (uint256 multiplier_) {
    multiplier_ = minesMultipliers[_numMines][_numRevealed];
  }

  /**
   * @dev get current game state of player
   * @param _player address of the player that made the bet
   * @return minesState_ current state of player game
   * @return currentPayout_ current payout if player were to end the game
   */
  function getState(
    address _player
  ) external view returns (Game memory minesState_, uint256 currentPayout_) {
    minesState_ = games[_player];
    currentPayout_ = (minesState_.currentMultiplier * minesState_.wager) / BASIS_POINTS;
    return (minesState_, currentPayout_);
  }

  /**
   * @dev Places a bet in the game.
   * @param _wager The amount of the wager.
   * @param _token The address of the token used for the wager.
   * @param _numMines The number of mines to be set in the game.
   * @param _cells An array representing the cells to reveal in the game.
   * @param _isCashout A boolean indicating whether the bet is a cashout or not.
   */
  function bet(
    uint256 _wager,
    address _token,
    uint8 _numMines,
    bool[25] calldata _cells,
    bool _isCashout
  ) external nonReentrant {
    // Ensure that the number of mines is within a valid range
    require(_numMines >= 1 && _numMines <= 24, "Mines: Invalid number of mines");

    // Retrieve the game information for the current player
    Game memory game_ = games[_msgSender()];

    // Ensure that the player is not already in a game
    require(game_.requestId == 0, "Mines: Awaiting random number");
    require(game_.numMines == 0, "Mines: Already in game");

    // Count the number of cells to reveal
    uint32 numCellsToReveal_;
    for (uint8 i = 0; i < 25; i++) {
      if (_cells[i]) {
        numCellsToReveal_++;
      }
    }

    // Get the maximum number of cells that can be revealed based on the number of mines
    uint256 minesMaxReveal_ = minesMaxReveal[_numMines];

    // Ensure that the number of cells to reveal is valid
    require(
      numCellsToReveal_ > 0 && numCellsToReveal_ <= minesMaxReveal_,
      "Mines: Invalid number of cells to reveal"
    );

    // Create a new game and get the request ID
    uint256 _requestId = _create(_numMines, _wager, _token, _isCashout, _cells);

    // Emit an event to indicate that the game has been created
    emit Created(_msgSender(), _wager, _token, _requestId, _numMines);
  }

  /**
   * @dev Ends the player's current game and receives the payout.
   * @dev This function is called by the player.
   * @dev Calls the internal _endGame function.
   */
  function endGame() external nonReentrant {
    _endGame(_msgSender());
  }

  /**
   * @dev Ends the player's current game and receives the payout.
   * @dev This function is called by the team.
   * @dev Calls the internal _endGame function.
   * @dev This function is for emergency use only. For stuck token in vault manager.
   * @param _player The address of the player to end the game for.
   */
  function endGameByTeam(address _player) external onlyTeam nonReentrant {
    Game memory game_ = games[_player];
    require(game_.startTime + endByTeamCooldown < block.timestamp, "Mines: Game not endable yet");
    _endGame(_player);
  }

  /**
   * @dev Ends the player's current game and receives the payout.
   */
  function _endGame(address _player) internal {
    // Retrieve the game information for the current player
    Game memory game_ = games[_player];

    // Ensure that the player is in a game
    require(game_.numMines > 0, "Mines: Not in game");
    require(game_.requestId == 0, "Mines: Awaiting random number");

    // Calculate the payout based on the current multiplier and wager
    uint256 multiplier_ = game_.currentMultiplier;
    uint256 wager_ = game_.wager;
    uint256 payout_ = (multiplier_ * wager_) / BASIS_POINTS;
    address token_ = game_.token;

    // Share the escrow between the player and the contract
    (, uint256 wagerWithMultiplier_) = shareEscrow(game_, wager_, payout_, game_.random);

    // Remove the player's game information
    delete (games[_player]);

    // Emit an event to indicate the end of the game and provide payout details
    emit Settled(_player, wager_, wagerWithMultiplier_, payout_, token_, multiplier_);
  }

  /**
   * @dev Reveals the specified cells in the player's current game.
   * @param _cells An array representing the cells to be revealed.
   * @param _isCashout A boolean indicating whether it is a cashout or not.
   */
  function revealCells(bool[25] calldata _cells, bool _isCashout) external nonReentrant {
    // Retrieve the game information for the current player
    // Game storage game_ = games[_msgSender()];
    Game memory game_ = games[_msgSender()];
    // Update the game information with the revealed cells and other details
    game_.cellsPicked = _cells;
    game_.isCashout = _isCashout;
    // game.startTime = block.timestamp;
    game_.startTime = uint64(block.timestamp);

    // Ensure that the player is in a game
    require(game_.numMines > 0, "Mines: Not in game");
    require(game_.requestId == 0, "Mines: Awaiting random number");

    // Count the number of cells revealed and to be revealed
    uint32 numCellsRevealed_;
    uint32 numCellsToReveal_;
    for (uint8 i = 0; i < 25; i++) {
      if (_cells[i]) {
        // Ensure that the cell hasn't been already revealed
        require(!game_.revealedCells[i], "Mines: Cell already revealed");
        numCellsToReveal_++;
      }
      if (game_.revealedCells[i]) {
        numCellsRevealed_++;
      }
    }

    // Ensure that the number of cells to reveal is valid
    require(
      numCellsToReveal_ != 0 &&
        numCellsToReveal_ + numCellsRevealed_ <= minesMaxReveal[game_.numMines],
      "Mines: Invalid number of cells to reveal"
    );

    // Request a random number for determining the cell outcomes
    uint256 id = _requestRandom(1);
    gameIds[id] = _msgSender();
    // game.requestId = id;
    game_.requestId = uint64(id);

    games[_msgSender()] = game_;
  }

  function randomizerFulfill(uint256 _requestId, uint256[] calldata _randoms) internal override {
    address player_ = gameIds[_requestId];
    delete (gameIds[_requestId]);
    Game storage game_ = games[player_];
    // game_.random = _randoms[0];
    game_.random = uint128(_randoms[0]);

    uint256 numberOfRevealedCells_;
    for (uint32 i = 0; i < game_.cellsPicked.length; i++) {
      if (game_.revealedCells[i] == true) {
        numberOfRevealedCells_++;
      }
    }
    uint256 numberOfMinesLeft_ = game_.numMines;
    bool[25] memory mines_;
    bool won_ = true;

    for (uint32 i = 0; i < game_.cellsPicked.length; i++) {
      if (numberOfMinesLeft_ == 0 || 25 - numberOfRevealedCells_ == numberOfMinesLeft_) {
        if (game_.cellsPicked[i]) {
          game_.revealedCells[i] = true;
        }
        continue;
      }
      if (game_.cellsPicked[i]) {
        bool gem = _pickCell(
          player_,
          i,
          25 - numberOfRevealedCells_,
          numberOfMinesLeft_,
          uint256(keccak256(abi.encodePacked(_randoms[0], i)))
        );
        if (gem == false) {
          numberOfMinesLeft_--;
          mines_[i] = true;
          won_ = false;
        }
        numberOfRevealedCells_ += 1;
      }
    }

    if (!won_) {
      if (game_.isCashout == false) {
        emit Reveal(player_, game_.wager, 0, game_.token, mines_, game_.revealedCells, 0);
      } else {
        emit RevealAndCashout(player_, game_.wager, 0, game_.token, mines_, game_.revealedCells, 0);
      }

      (, uint256 wagerWithMultiplier_) = shareEscrow(game_, game_.wager, 0, game_.random);
      emit Settled(player_, game_.wager, wagerWithMultiplier_, 0, game_.token, 0);
      delete (games[player_]);

      return;
    }

    uint256 multiplier_ = minesMultipliers[numberOfMinesLeft_][numberOfRevealedCells_];
    uint256 payout_ = (multiplier_ * game_.wager) / BASIS_POINTS;

    if (game_.isCashout == false) {
      game_.currentMultiplier = uint64(multiplier_);
      game_.requestId = 0;
      emit Reveal(
        player_,
        game_.wager,
        payout_,
        game_.token,
        mines_,
        game_.revealedCells,
        multiplier_
      );
    } else {
      uint256 wager_ = game_.wager;
      address token_ = game_.token;
      emit RevealAndCashout(
        player_,
        wager_,
        payout_,
        token_,
        mines_,
        game_.revealedCells,
        multiplier_
      );

      (, uint256 wagerWithMultiplier_) = shareEscrow(game_, wager_, payout_, game_.random);
      emit Settled(player_, wager_, wagerWithMultiplier_, payout_, token_, multiplier_);

      delete (games[player_]);
    }
  }

  function _pickCell(
    address _player,
    uint256 _cellNumber,
    uint256 _numberCellsLeft,
    uint256 _numberOfMinesLeft,
    uint256 _random
  ) internal returns (bool) {
    uint256 winChance = BASIS_POINTS - (_numberOfMinesLeft * BASIS_POINTS) / _numberCellsLeft;

    bool won_ = false;
    if (_random % BASIS_POINTS <= winChance) {
      won_ = true;
    }
    games[_player].revealedCells[_cellNumber] = true;
    return won_;
  }

  /**
   * @dev function to set game max number of reveals only callable at deploy time
   * @param maxReveal max reveal for each num Mines
   */
  function setMaxReveal(uint8[24] memory maxReveal) external onlyGovernance {
    for (uint8 i = 0; i < maxReveal.length; i++) {
      minesMaxReveal[i + 1] = maxReveal[i];
    }
  }
}

