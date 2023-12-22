// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./CommonKeno.sol";
import "./InternalRNG.sol";

contract Keno is CommonSoloKeno, InternalRNG {
  uint256 public constant amountNumbers = 40;
  uint256 public constant amountUniqueDraws = 10;
  uint256 internal immutable minWagerValue;

  // amount of picks => multiplier of amount numbers correct[0-10]
  mapping(uint256 => uint256[11]) internal multipliers_;
  mapping(uint256 => uint256) internal houseEdges_;

  constructor(IRandomizerRouter _router, uint256 _minWagerValue) CommonSoloKeno(_router) {
    // Pre defined multipliers_
    // picks => []amount corect
    //  multipliers_[9][6] -> multiplier for 9 picks and 6 correct
    multipliers_[1] = [40, 240, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    multipliers_[2] = [0, 160, 500, 0, 0, 0, 0, 0, 0, 0, 0];
    multipliers_[3] = [0, 0, 220, 5000, 0, 0, 0, 0, 0, 0, 0];
    multipliers_[4] = [0, 0, 150, 900, 1e4, 0, 0, 0, 0, 0, 0];
    multipliers_[5] = [0, 0, 140, 300, 1400, 4 * 1e4, 0, 0, 0, 0, 0];
    multipliers_[6] = [0, 0, 0, 300, 800, 15 * 1e3, 7 * 1e4, 0, 0, 0, 0];
    multipliers_[7] = [0, 0, 0, 200, 600, 2500, 4 * 1e4, 8 * 1e4, 0, 0, 0];
    multipliers_[8] = [0, 0, 0, 200, 300, 1000, 6500, 4 * 1e4, 9 * 1e4, 0, 0];
    multipliers_[9] = [0, 0, 0, 200, 230, 400, 900, 1e4, 5 * 1e4, 1e5, 0];
    multipliers_[10] = [
      0 /** 10 picks, 0 correct */,
      0,
      0,
      130,
      200,
      400,
      700,
      2500,
      1e4,
      5 * 1e4,
      1e5 /** 10 picks, 10 correct */
    ];

    // Pre defined houseEdges_
    houseEdges_[0] = 0;
    houseEdges_[1] = 100;
    houseEdges_[2] = 96;
    houseEdges_[3] = 92;
    houseEdges_[4] = 95;
    houseEdges_[5] = 86;
    houseEdges_[6] = 96;
    houseEdges_[7] = 86;
    houseEdges_[8] = 100;
    houseEdges_[9] = 77;
    houseEdges_[10] = 97;

    minWagerValue = _minWagerValue;
  }

  function checkWagerValue(uint256 _wager, address _token) internal view {
    uint256 dollarValue_ = _computeDollarValue(_token, _wager);
    require(dollarValue_ >= minWagerValue, "Keno: wager is too small");
    require(dollarValue_ <= vaultManager.getMaxWager(), "Keno: wager is too big");
  }

  /*==================================================== Functions ===========================================================*/

  function updateMultipliers_(
    uint256 _picks,
    uint256[10] memory _multipliers,
    uint64 _houseEdge
  ) external onlyGovernance {
    require(_multipliers.length == 10, "Keno: insufficient _multipliers_ length");
    multipliers_[_picks] = _multipliers;
    houseEdges_[_picks] = _houseEdge;
  }

  function getHouseEdge(Game memory _game) public view override returns (uint64 edge_) {
    edge_ = uint64(houseEdges_[_game.gameData.length]);
  }

  function getMultipliersOfPick(
    uint256 _picks
  ) public view returns (uint256[11] memory multiplierArray_) {
    multiplierArray_ = multipliers_[_picks];
  }

  function getMultiplier(
    uint256 _picks,
    uint256 _correct
  ) public view returns (uint256 multiplierOfGame_) {
    multiplierOfGame_ = multipliers_[_picks][_correct];
  }

  function calcReward(
    uint256 _picks,
    uint256 _correct,
    uint256 _wager
  ) internal view returns (uint256 reward_) {
    uint256 multiplier = multipliers_[_picks][_correct];
    unchecked {
      reward_ = (_wager * multiplier) / 1e2;
    }
  }

  function houseEdges(uint32 _picks) external view returns (uint64 houseEdge_) {
    houseEdge_ = uint64(houseEdges_[_picks]);
  }

  /**
   * @notice function that takes the vrf randomness and returns the keno result numbers
   * @dev in keno no drawn number can be repeated, therefor we use Fisher - Yates shuffle of a 40 numbers array
   * @param _randoms the random value of the vrf
   */
  function getResultNumbers(
    uint256 _randoms
  ) internal pure override returns (uint256[] memory resultNumbers_) {
    uint256[] memory allNumbersArray_ = new uint256[](amountNumbers);
    resultNumbers_ = new uint256[](10);

    unchecked {
      // Initialize an array with values from 1 to 40
      for (uint256 i = 0; i < amountNumbers; ++i) {
        allNumbersArray_[i] = i + 1;
      }

      // Perform a Fisher-Yates shuffle to randomize the array
      for (uint256 y = 39; y >= 1; --y) {
        uint256 value_ = uint256(keccak256(abi.encodePacked(_randoms, y))) % (y + 1);
        (allNumbersArray_[y], allNumbersArray_[value_]) = (
          allNumbersArray_[value_],
          allNumbersArray_[y]
        );
      }

      // Select the first 10 numbers from the shuffled array
      for (uint256 x = 0; x < amountUniqueDraws; ++x) {
        resultNumbers_[x] = allNumbersArray_[x];
      }
    }

    return resultNumbers_;
  }

  /**
   *
   * @param _randomNumbers array with random numbers
   * @param _playerChoices array with player number choices
   * @param _wager wager amount of the player
   */
  function _checkHowMuchCorrect(
    uint256[] memory _randomNumbers,
    uint32[] memory _playerChoices,
    uint256 _wager
  ) internal view returns (uint256 reward_) {
    require(_randomNumbers.length == amountUniqueDraws, "Keno: _random  must be of length 10");
    require(_playerChoices.length <= amountUniqueDraws, "Keno: _random invalid length");

    bool[amountNumbers] memory exists_;
    unchecked {
      // Create a boolean array that can handle up to 100 values
      for (uint i = 0; i < _randomNumbers.length; i++) {
        // Subtract one because array indices are 0-based
        exists_[_randomNumbers[i] - 1] = true;
      }
    }

    uint256 amountCorrect_;

    unchecked {
      // Check overlaps / correct numbers ->  amountCorrect_
      amountCorrect_ = 0;
      for (uint x = 0; x < _playerChoices.length; x++) {
        if (exists_[_playerChoices[x] - 1]) {
          amountCorrect_++;
        }
      }
    }

    reward_ = calcReward(_playerChoices.length, amountCorrect_, _wager);
  }

  /**
   * @param _game game data struct
   * @param _randoms array with random values
   * @param _stopGain stopgain amount
   * @param _stopLoss stoploss amount
   * @return payout_ total payout amount of all rounds combined
   * @return playedGameCount_ count of played games_
   * @return payouts_ array with payouts per round
   */
  function play(
    uint256 _requestId,
    Game memory _game,
    uint256[] memory _randoms,
    uint128 _stopGain,
    uint128 _stopLoss
  )
    internal
    override
    returns (uint256 payout_, uint256 playedGameCount_, uint256[] memory payouts_)
  {
    payouts_ = new uint[](_game.count);
    playedGameCount_ = uint256(_game.count);
    uint32[] memory choices_ = new uint32[](_game.gameData.length);
    choices_ = _game.gameData;

    for (uint256 i = 0; i < playedGameCount_; ++i) {
      // convert the random value to the result numbers (10 picks, between 1-40, no repeats)
      uint256[] memory resultNumbers_ = getResultNumbers(_randoms[i]);
      // check how much correct numbers the player has
      uint256 reward_ = _checkHowMuchCorrect(resultNumbers_, choices_, _game.wager);
      payouts_[i] = reward_;
      unchecked {
        payout_ += reward_;
      }
      if (i == 0) {
        gameDraws_[_requestId].firstDraw = [
          uint32(resultNumbers_[0]),
          uint32(resultNumbers_[2]),
          uint32(resultNumbers_[1]),
          uint32(resultNumbers_[3]),
          uint32(resultNumbers_[4]),
          uint32(resultNumbers_[5]),
          uint32(resultNumbers_[6]),
          uint32(resultNumbers_[7]),
          uint32(resultNumbers_[8]),
          uint32(resultNumbers_[9])
        ];
      } else if (i == 1) {
        gameDraws_[_requestId].secondDraw = [
          uint32(resultNumbers_[0]),
          uint32(resultNumbers_[1]),
          uint32(resultNumbers_[2]),
          uint32(resultNumbers_[3]),
          uint32(resultNumbers_[4]),
          uint32(resultNumbers_[5]),
          uint32(resultNumbers_[6]),
          uint32(resultNumbers_[7]),
          uint32(resultNumbers_[8]),
          uint32(resultNumbers_[9])
        ];
      } else if (i == 2) {
        gameDraws_[_requestId].thirdDraw = [
          uint32(resultNumbers_[0]),
          uint32(resultNumbers_[1]),
          uint32(resultNumbers_[2]),
          uint32(resultNumbers_[3]),
          uint32(resultNumbers_[4]),
          uint32(resultNumbers_[5]),
          uint32(resultNumbers_[6]),
          uint32(resultNumbers_[7]),
          uint32(resultNumbers_[8]),
          uint32(resultNumbers_[9])
        ];
      } else {
        revert("Keno: Can't play more than 3 games_");
      }
      emit KenoResult(_game.player, i, _requestId, resultNumbers_);
      if (shouldStop(payout_, (i + 1) * _game.wager, _stopGain, _stopLoss)) {
        playedGameCount_ = i + 1;
        break;
      }
    }
  }

  /**
   * @notice function that checks if the players choice is valid
   * @dev in Keno player needs to chose between 1 and 10 numbers
   * @dev player cannot chose the same number multiple times
   * @param _gameData the chosen numbers of the player
   */
  function _processPlayerChoice(uint32[] memory _gameData) internal pure {
    uint256 length_ = _gameData.length;
    require(length_ != 0, "Keno: Can't choose less than 1 number");
    require(length_ <= 10, "Keno: Can't choose more than 10 numbers");
    bool[40] memory exists;

    unchecked {
      // can't choose more than 10 numbers
      for (uint256 i = 0; i < length_; ++i) {
        require(_gameData[i] != 0, "Keno: Choice 0 isn't allowed");
        require(_gameData[i] <= 40, "Keno: Choice larger as 40 isn't allowed");
        // Subtract one because array indices are 0-based
        if (exists[_gameData[i] - 1]) {
          // This value is a duplicate
          revert("Keno: Number not available/alreadychosen");
        }
        exists[_gameData[i] - 1] = true;
      }
    }
  }

  /**
   * @param _wager wager amount in token per game round
   * @param _count max amount of games_ rounds to play
   * @param _stopGain take profit amount in token
   * @param _stopLoss stoploss amount in token
   * @param _gameData array with number choices
   * @param _token token address of wager
   */
  function bet(
    uint128 _wager,
    uint8 _count,
    uint128 _stopGain,
    uint128 _stopLoss,
    uint32[] memory _gameData,
    address _token
  ) external {
    _bet(_wager, _count, _stopGain, _stopLoss, _gameData, _token);
  }

  function _bet(
    uint128 _wager,
    uint8 _count,
    uint128 _stopGain,
    uint128 _stopLoss,
    uint32[] memory _gameData,
    address _token
  ) internal {
    require(_count != 0, "Keno: Game count null");
    require(_count <= maxGameCount, "Keno: Game count out-range");
    checkWagerValue(_wager, _token);
    _processPlayerChoice(_gameData);
    _create(_wager, _count, _stopGain, _stopLoss, _gameData, _token);
  }
}

