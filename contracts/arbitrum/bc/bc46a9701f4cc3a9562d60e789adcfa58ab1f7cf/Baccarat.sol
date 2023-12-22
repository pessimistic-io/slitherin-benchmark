// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./CommonBaccarat.sol";
import "./InternalRNG.sol";

contract Baccarat is CommonSoloBaccarat, InternalRNG {
  uint256 public constant multiplierTie = 900;
  uint256 public constant multiplierBanker = 195;
  uint256 public constant multiplierPlayer = 200;
  uint64 public constant houseEdge = 98; // note we can just use uin256 because it uses a strorage slot anyway

  enum BaccaratResult {
    UNDECIDED,
    PLAYER_WINS,
    BANK_WINS,
    DRAW
  }

  // player has third card, rules banker for third card
  bool[10] internal bankerPuntoThree = [
    true,
    true /** banker has 3 points, player draws ace, 3rd card for banker */,
    true,
    true,
    true,
    true,
    true,
    true,
    false,
    true
  ];

  bool[10] internal bankerPuntoFour = [
    false, // 0
    false, // 1
    true, // 2
    true, // 3
    true, // 4
    true, // 5
    true, // 6
    true, // 7
    false, // 8
    false // 9
  ];

  bool[10] internal bankerPuntoFive = [
    false, // 0
    false, // 1
    false, // 2
    false, // 3
    true, // 4
    true, // 5
    true, // 6
    true, // 7
    false, // 8
    false // 9
  ];

  bool[10] internal bankerPuntoSix = [
    false, // 0
    false, // 1
    false, // 2
    false, // 3
    false, // 4
    false, // 5
    true, // 6
    true, // 7
    false, // 8
    false // 9
  ];

  constructor(IRandomizerRouter _router) CommonSoloBaccarat(_router) {}

  function getResultNumbers(
    uint256 _randoms
  ) internal pure override returns (uint256[6] memory topCards_) {
    uint256[312] memory allNumbersDecks_;

    uint256 index_ = 0;

    unchecked {
      // Loop for 6 decks
      for (uint256 i = 0; i < 6; ++i) {
        for (uint256 t = 0; t < 4; ++t) {
          // 14 different types of cards in each deck
          for (uint256 x = 1; x <= 13; ++x) {
            // console.log("index_ %s", index_);
            allNumbersDecks_[index_] = x;
            index_++;
          }
        }
      }
    }

    // allNumbersDecks_ represents a deck of 6 cards, with 1 being the Ace, and 13 the king, it currently contains 312 numbers perfectly sorted per number.

    unchecked {
      // Perform a Fisher-Yates shuffle to randomize the array/deck
      for (uint256 y = 311; y >= 1; --y) {
        uint256 value_ = uint256(keccak256(abi.encodePacked(_randoms, y))) % (y + 1);
        (allNumbersDecks_[y], allNumbersDecks_[value_]) = (
          allNumbersDecks_[value_],
          allNumbersDecks_[y]
        );
      }
    }

    unchecked {
      // Select the first 6 cards from the shuffled deck (from the top)
      for (uint256 x = 0; x < 6; ++x) {
        uint256 value_ = allNumbersDecks_[x];
        // note this is uncommented, but previously we converted the card value to the amount of points, so this if statement would turn 10 and the face cards to 0 puntos
        topCards_[x] = value_;
      }
    }

    return topCards_;
  }

  function _scaleValueToPunto(uint256 _value) internal pure returns (uint256) {
    if (_value >= 10) {
      return 0;
    }
    return _value;
  }

  function getHouseEdge() public pure override returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /**
   * @notice Calculates the punto total for the player hand
   * @param _game the game struct to calculate the punto for
   */
  function calculatePlayerPuntoTotal(
    BaccaratGame memory _game
  ) public pure returns (uint256 total_) {
    // the player hand has a third card (according to the rules)
    if (_game.playerHand.hasThirdCard) {
      total_ =
        (_scaleValueToPunto(_game.playerHand.firstCard) +
          _scaleValueToPunto(_game.playerHand.secondCard) +
          _scaleValueToPunto(_game.playerHand.thirdCard)) %
        10;
    } else {
      // the dealt third card is not included in the calculation
      total_ =
        (_scaleValueToPunto(_game.playerHand.firstCard) +
          _scaleValueToPunto(_game.playerHand.secondCard)) %
        10;
    }
  }

  /**
   * @notice Calculates the punto total for the banker hand
   * @param _game the game struct to calculate the punto for
   */
  function calculateBankerPuntoTotal(
    BaccaratGame memory _game
  ) public pure returns (uint256 total_) {
    // the banker hand has a third card (according to the rules)
    if (_game.bankerHand.hasThirdCard) {
      total_ =
        (_scaleValueToPunto(_game.bankerHand.firstCard) +
          _scaleValueToPunto(_game.bankerHand.secondCard) +
          _scaleValueToPunto(_game.bankerHand.thirdCard)) %
        10;
      // the banker hand does not have a third card (according to the rules)
    } else {
      // the dealt third card is not included in the calculation
      total_ =
        (_scaleValueToPunto(_game.bankerHand.firstCard) +
          _scaleValueToPunto(_game.bankerHand.secondCard)) %
        10;
    }
  }

  /**
   * @notice returns who has won a certain game
   * @param _requestId the requestId of the game to check the winner for
   */
  function whoIsWinner(uint256 _requestId) public view returns (BaccaratResult result_) {
    BaccaratGame memory game_ = games_[_requestId];
    uint256 playerTotal_ = calculatePlayerPuntoTotal(game_);
    uint256 bankTotal_ = calculateBankerPuntoTotal(game_);
    return _checkWinner(playerTotal_, bankTotal_);
  }

  /**
   * @notice returns the player punto for a certain game
   * @param _requestId the requestId of the game to check the player punto for
   * @return playerPunto_ the player punto for the game
   */
  function getPlayerPunto(uint256 _requestId) public view returns (uint256 playerPunto_) {
    BaccaratGame memory game_ = games_[_requestId];
    playerPunto_ = calculatePlayerPuntoTotal(game_);
  }

  /**
   * @notice returns the banker punto for a certain game
   * @param _requestId the requestId of the game to check the banker punto for
   * @return bankerPunto_ the banker punto for the game
   */
  function getBankerPunto(uint256 _requestId) public view returns (uint256 bankerPunto_) {
    BaccaratGame memory game_ = games_[_requestId];
    bankerPunto_ = calculateBankerPuntoTotal(game_);
  }

  /**
   * @param _playerTotal amount punto for player
   * @param _bankTotal amount punto for banker
   */
  function _checkWinner(
    uint256 _playerTotal,
    uint256 _bankTotal
  ) internal pure returns (BaccaratResult result_) {
    if (_playerTotal == _bankTotal) {
      return BaccaratResult.DRAW;
    } else if (_playerTotal > _bankTotal) {
      return BaccaratResult.PLAYER_WINS;
    } else {
      return BaccaratResult.BANK_WINS;
    }
  }

  /**
   * @param _playerTotal amount punto for player
   * @param _bankTotal amount punto for banker
   */
  function _checkImmediateWinner(
    uint256 _playerTotal,
    uint256 _bankTotal
  ) internal pure returns (BaccaratResult result_) {
    if (_playerTotal > 7 || _bankTotal > 7) {
      // either bank or player have 8 or 9 (higher than 7)
      if (_playerTotal == _bankTotal) {
        // both bank and player have 8 or 9, its a draw
        return BaccaratResult.DRAW;
      } else if (_playerTotal > _bankTotal) {
        return BaccaratResult.PLAYER_WINS;
      } else {
        return BaccaratResult.BANK_WINS;
      }
    } else {
      return BaccaratResult.UNDECIDED;
    }
  }

  function _calculateWinnings(
    BaccaratResult result_,
    Bet memory _betInfo
  ) internal pure returns (uint256 payout_) {
    uint256 betAmount_;
    unchecked {
      if (result_ == BaccaratResult.DRAW) {
        betAmount_ = _chip2TokenDecimals(
          _betInfo.tieWinsInChips,
          _betInfo.decimals,
          _betInfo.tokenPrice
        );
        payout_ = (betAmount_ * multiplierTie) / 1e2;
        // check how much chips where bet on player or banke
        uint256 totalChipsOnPlayerOrBanker_ = _betInfo.bankWinsInChips + _betInfo.playerWinsInChips;
        if (totalChipsOnPlayerOrBanker_ != 0) {
          // the player has bes on either player or banker, so we need to return the chips bet on player or banker
          uint256 returnAmount_ = _chip2TokenDecimals(
            totalChipsOnPlayerOrBanker_,
            _betInfo.decimals,
            _betInfo.tokenPrice
          );
          payout_ += returnAmount_;
        } else {
          // player hasn't bet on player on banker
          return payout_;
        }
      } else if (result_ == BaccaratResult.PLAYER_WINS) {
        betAmount_ = _chip2TokenDecimals(
          _betInfo.playerWinsInChips,
          _betInfo.decimals,
          _betInfo.tokenPrice
        );
        payout_ = (betAmount_ * multiplierPlayer) / 1e2;
      } else {
        // the banker must have won
        betAmount_ = _chip2TokenDecimals(
          _betInfo.bankWinsInChips,
          _betInfo.decimals,
          _betInfo.tokenPrice
        );
        payout_ = (betAmount_ * multiplierBanker) / 1e2;
      }
    }
    return payout_;
  }

  function play(
    uint256 _requestId,
    Bet memory _betInfo,
    uint256 _random
  ) internal override returns (uint256 payout_) {
    // shuffle 6 decks, take 6 first cards (random Fisher-Yates shuffle)
    uint256[6] memory topCards_ = getResultNumbers(_random);

    // deal top card to player, and the next to the bank, then the next to the player, then the next to the bank
    uint256 playerCount_;
    uint256 bankCount_;

    unchecked {
      playerCount_ = _scaleValueToPunto(topCards_[0]) + _scaleValueToPunto(topCards_[2]);
      bankCount_ = _scaleValueToPunto(topCards_[1]) + _scaleValueToPunto(topCards_[3]);
    }

    Hand memory playerHand_ = Hand({
      hasThirdCard: false,
      firstCard: uint8(topCards_[0]),
      secondCard: uint8(topCards_[2]),
      thirdCard: uint8(topCards_[4])
    });

    Hand memory bankerHand_ = Hand({
      hasThirdCard: false,
      firstCard: uint8(topCards_[1]),
      secondCard: uint8(topCards_[3]),
      thirdCard: uint8(topCards_[5])
    });

    // if either banker or players punto is 8 or 9, the game is over and no more cards are dealt (for either hands)
    if (_checkImmediateWinner(playerCount_ % 10, bankCount_ % 10) != BaccaratResult.UNDECIDED) {
      // game ended, either player or banker ahve 8 or 9, calculate potential payout for the game
      payout_ = _calculateWinnings(_checkWinner(playerCount_ % 10, bankCount_ % 10), _betInfo);
      emit HandFinalized(games_[_requestId].player, _requestId, playerHand_, bankerHand_);
      games_[_requestId].bankerHand = bankerHand_;
      games_[_requestId].playerHand = playerHand_;
      return payout_;
    }

    // neither the banker or the player has 8 or 9, game continues
    // first check if player gets third card based on the first two cards of the player

    // if player has 6 or 7 points, no third card for player
    if ((playerCount_ % 10) < 6) {
      // player punto is 1,2,3,4,5 -> player gets third card
      unchecked {
        playerCount_ += _scaleValueToPunto(topCards_[4]);
      }
      // register that player has gotten third card
      playerHand_.hasThirdCard = true;
    } else {
      // the player stands (no third card) so player has 6 or 7, check if the bank gets a third card according to the rules
      if ((bankCount_ % 10) < 6) {
        // bank punto is 1,2,3,4,5 -> bank gets third card
        unchecked {
          bankCount_ += _scaleValueToPunto(topCards_[5]);
        }
        // register that bank has gotten third card
        bankerHand_.hasThirdCard = true;
      }
      // game is over, calculate payout
      payout_ = _calculateWinnings(_checkWinner(playerCount_ % 10, bankCount_ % 10), _betInfo);
      emit HandFinalized(games_[_requestId].player, _requestId, playerHand_, bankerHand_);
      games_[_requestId].bankerHand = bankerHand_;
      games_[_requestId].playerHand = playerHand_;
      return payout_;
    }

    // note if we are here it is still possible that the player has 2 or 3 cards, the bank certainly has only 2 cards at this point

    // when bank has punto 7, no new card for banker, game ends
    // note this is a bit redundant code because this is also in the schema? but it is a good check
    if ((bankCount_ % 10) == 7) {
      bankerHand_.hasThirdCard = false;
      // emit HandFinalized(games_[_requestId].player, _requestId, playerHand_, bankerHand_);
      emit HandFinalized(games_[_requestId].player, _requestId, playerHand_, bankerHand_);

      payout_ = _calculateWinnings(_checkWinner(playerCount_ % 10, bankCount_ % 10), _betInfo);
      games_[_requestId].bankerHand = bankerHand_;
      games_[_requestId].playerHand = playerHand_;
      return payout_;
    }

    // if player has a thrid card, and the banker not yet, the bank will get a third card depending on the third drawn card of the player and the bankers total punto
    if (playerHand_.hasThirdCard && !bankerHand_.hasThirdCard) {
      // check if bank gets third card (according to the specific mapping for this stage of the hand)
      bool thirdCard_ = _doesBankerGetThirdCard(_scaleValueToPunto(topCards_[4]), bankCount_ % 10);
      if (thirdCard_) {
        // banker gets third card
        unchecked {
          bankCount_ += _scaleValueToPunto(topCards_[5]);
        }
        // register that bank has gotten third card
        bankerHand_.hasThirdCard = true;
      }
    }

    games_[_requestId].bankerHand = bankerHand_;
    games_[_requestId].playerHand = playerHand_;

    emit HandFinalized(games_[_requestId].player, _requestId, playerHand_, bankerHand_);

    // calculate how much the payout is (in tokens)
    payout_ = _calculateWinnings(_checkWinner(playerCount_ % 10, bankCount_ % 10), _betInfo);

    return payout_;
  }

  /**
   * @notice returns if the bank gets a third card
   * @param _thirdCard the third card of the player (amount of points/puntos)
   * @param _puntoBanker how much puntos the banker has with the first two cards
   * @return thirdCard_ if the bank gets a third card. true = third card, false = no third card
   */
  function _doesBankerGetThirdCard(
    uint256 _thirdCard,
    uint256 _puntoBanker
  ) internal view returns (bool thirdCard_) {
    if (_puntoBanker < 3) {
      return true;
    } else if (_puntoBanker == 3) {
      return bankerPuntoThree[_thirdCard];
    } else if (_puntoBanker == 4) {
      return bankerPuntoFour[_thirdCard];
    } else if (_puntoBanker == 5) {
      return bankerPuntoFive[_thirdCard];
    } else if (_puntoBanker == 6) {
      return bankerPuntoSix[_thirdCard];
    } else {
      require(_puntoBanker == 7, "Baccarat: Punto cannot be higher than 7.");
      return false;
    }
  }

  /**
   * @notice internal function that checks if bet is allowed and does chip to token conversion
   * @param _tieWinsChips amount of chips wagered on tie
   * @param _bankWinsChips amount of chips wagered on banker win
   * @param _playerWinsChips amount of chips wagered on player win
   * @param _token address of the token wagered
   * @return betInfo_ bet info struct
   * @return wagerAmount_ amount of tokens wagered
   */
  function _checkWagerReturn(
    uint24 _tieWinsChips,
    uint24 _bankWinsChips,
    uint24 _playerWinsChips,
    address _token
  ) internal returns (Bet memory betInfo_, uint256 wagerAmount_) {
    uint256 totalWagerChips_ = uint256(_tieWinsChips + _bankWinsChips + _playerWinsChips);
    uint256 price_ = vaultManager.getPrice(_token);
    (uint256 tokenAmount_, uint256 dollarValue_) = _chip2Token(totalWagerChips_, _token, price_);
    require(dollarValue_ <= vaultManager.getMaxWager(), "Baccarat: wager is too big");
    require(dollarValue_ >= minWagerAmount, "Baccarat: Wager too low");
    betInfo_ = Bet({
      gameCompleted: false,
      tokenPrice: uint144(price_),
      totalWagerInChips: uint24(totalWagerChips_),
      tieWinsInChips: uint24(_tieWinsChips),
      bankWinsInChips: uint24(_bankWinsChips),
      playerWinsInChips: uint24(_playerWinsChips),
      decimals: uint8(_getDecimals(_token))
    });
    return (betInfo_, tokenAmount_);
  }

  /**
   * @notice main betting function for baccarat
   * @param _tieWins amount chips wagered on tie
   * @param _bankWins amount chips wagered on banker win
   * @param _playerWins amount chips wagered on player win
   * @param _token address of the token wagered
   */
  function bet(uint24 _tieWins, uint24 _bankWins, uint24 _playerWins, address _token) external {
    _bet(_tieWins, _bankWins, _playerWins, _token);
  }

  function _bet(uint24 _tieWins, uint24 _bankWins, uint24 _playerWins, address _token) internal {
    (Bet memory bet_, uint256 wagerAmout_) = _checkWagerReturn(
      _tieWins,
      _bankWins,
      _playerWins,
      _token
    );
    _create(bet_, wagerAmout_, _token);
  }
}

