// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Common.sol";

contract Slot is CommonSolo {
  /*==================================================== Events ==========================================================*/

  event UpdateHouseEdge(uint64 houseEdge);
  event MultipliersUpdated(uint256[] outcomeNums, uint256[] newMultipliers);

  /*==================================================== State Variables ====================================================*/

  /// @notice number of combinations of game
  uint32 public combinationCount = 343;
  /// @notice house edge of game
  uint64 public houseEdge = 200;
  /// @notice multipliers of game
  mapping(uint256 => uint256) public multipliers;

  constructor(IRandomizerRouter _router) CommonSolo(_router) {}

  /*==================================================== EXTERNAL FUNCTIONS ===========================================================*/
  ///@notice function that updates multipliers
  ///@param _outcomeNums outcome number of game
  ///@param _newMultipliers new multiplier of game
  ///@notice should set old outcomes to zero if you want to remove them
  function updateMultipliersBatch(
    uint256[] memory _outcomeNums,
    uint256[] memory _newMultipliers
  ) external onlyGovernance {
    require(_outcomeNums.length == _newMultipliers.length, "Slot: length mismatch");

    // update multipliers and outcome numbers array
    for (uint256 i = 0; i < _outcomeNums.length; ++i) {
      multipliers[_outcomeNums[i]] = _newMultipliers[i];
    }

    emit MultipliersUpdated(_outcomeNums, _newMultipliers);
  }

  /// @notice function that set house edge
  /// @param _houseEdge edge percent of game eg. 1000 = 10.00
  function updateHouseEdge(uint64 _houseEdge) external onlyGovernance {
    houseEdge = _houseEdge;

    emit UpdateHouseEdge(_houseEdge);
  }

  /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory) public view override returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /// @notice calculates winning multiplier for choices
  /// @param _result random number that modded with combinationCount
  function getMultiplier(uint256 _result) public view returns (uint256 multiplier_) {
    multiplier_ = multipliers[_result] * PRECISION;
  }

  /// @notice calculates reward results
  /// @param _result random number that modded with combinationCount
  /// @param _wager players wager for a game
  function calcReward(uint256 _result, uint256 _wager) public view returns (uint256 reward_) {
    reward_ = (_wager * getMultiplier(_result)) / PRECISION;
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory,
    uint256[] calldata _randoms
  ) internal view override returns (uint256[] memory numbers_) {
    numbers_ = modNumbers(_randoms, combinationCount);
  }

  /// @notice game logic contains here, decision mechanism
  /// @param _game request's game
  /// @param _resultNumbers modded numbers according to game
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @return payout_ _payout accumulated payouts by game contract
  /// @return playedGameCount_  played game count by game contract
  /// @return payouts_ profit calculated at every step of the game, wager excluded
  function play(
    Game memory _game,
    uint256[] memory _resultNumbers,
    uint256 _stopGain,
    uint256 _stopLoss
  )
    public
    view
    override
    returns (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_)
  {
    payouts_ = new uint[](_game.count);
    playedGameCount_ = _game.count;

    for (uint8 i = 0; i < _game.count; ++i) {
      uint256 reward_ = calcReward(_resultNumbers[i], _game.wager);

      payouts_[i] = reward_ > _game.wager ? reward_ - _game.wager : 0;
      payout_ += reward_;

      if (shouldStop(payout_, (i + 1) * _game.wager, _stopGain, _stopLoss)) {
        playedGameCount_ = i + 1;
        break;
      }
    }
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _wager amount for a game
  /// @param _count the selected game count by player
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @param _gameData players decisions according to game, should be zero for this game
  /// @param _token which token will be used for a game
  function bet(
    uint256 _wager,
    uint8 _count,
    uint256 _stopGain,
    uint256 _stopLoss,
    bytes memory _gameData,
    address _token
  ) external {
    _create(_wager, _count, _stopGain, _stopLoss, _gameData, _token);
  }
}

