// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Core.sol";

contract Roulette is Core {
  /*==================================================== Events ==========================================================*/

  event UpdateHouseEdge(uint64 houseEdge);

  event ConfigurationUpdated(Configuration configuration);

  event Created(
    uint8[145] selections,
    uint8 count,
    address token,
    address indexed player,
    uint64 requestId,
    uint128 price
  );

  event Settled(address indexed player, uint64 requestId, uint256 payout, uint256[] outcomes);

  /*==================================================== State Variables ====================================================*/

  struct Game {
    uint8[145] selections;
    uint8 count;
    address token;
    address player;
    uint64 startTime;
    uint128 totalWagerInToken;
    uint128 price;
  }

  struct Chunk {
    uint64 selector;
    uint64 multiplier;
  }

  struct Configuration {
    uint8 maxCount;
    uint64 minChip;
    uint64 maxChip;
  }

  /// @notice the number is used calculate singular selections
  uint8 public singleNumberMultiplier = 36;
  /// @notice chunk multipliers are used to get multiplier without making any calculation
  uint8[108] public chunkMultipliers;
  /// @notice chunk maps are used to easy access to selections which has included the number
  uint8[][37] public chunkMaps;
  /// @notice cooldown duration to refund
  uint32 public refundCooldown = 2 hours; // default value
  /// @notice house edge of game, used to calculate referrals share (200 = 2.00)
  uint64 public houseEdge = 200;
  /// @notice maxChip can be up to 256, even if the maxChip configured
  /// @notice the total wager also will be checked over max wager of the platform
  Configuration public configuration = Configuration(50, 1, 250);
  /// @notice stores all games
  mapping(uint64 => Game) public games;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) Core(_router) {
// for 0,1,2 
chunkMultipliers[0] = 12;
// for 0,2,3 
chunkMultipliers[1] = 12;
// for 1,2,4,5 
chunkMultipliers[2] = 9;
// for 2,3,5,6
chunkMultipliers[3] = 9;
// for 4,5,7,8 
chunkMultipliers[4] = 9;
// for 5,6,8,9 
chunkMultipliers[5] = 9;
// for 10,11,7,8 
chunkMultipliers[6] = 9;
// for 11,12,8,9 
chunkMultipliers[7] = 9;
// for 11,12,14,15 
chunkMultipliers[8] = 9;
// for 10,11,13,14 
chunkMultipliers[9] = 9;
// for 14,15,17,18 
chunkMultipliers[10] = 9;
// for 13,14,16,17 
chunkMultipliers[11] = 9;
// for 17,18,20,21 
chunkMultipliers[12] = 9;
// for 16,17,19,20 
chunkMultipliers[13] = 9;
// for 20,21,23,24 
chunkMultipliers[14] = 9;
// for 19,20,22,23 
chunkMultipliers[15] = 9;
// for 23,24,26,27 
chunkMultipliers[16] = 9;
// for 22,23,25,26 
chunkMultipliers[17] = 9;
// for 26,27,29,30 
chunkMultipliers[18] = 9;
// for 25,26,28,29 
chunkMultipliers[19] = 9;
// for 29,30,32,33 
chunkMultipliers[20] = 9;
// for 28,29,31,32  
chunkMultipliers[21] = 9;
// for 32,33,35,36 
chunkMultipliers[22] = 9;
// for 31,32,34,35 
chunkMultipliers[23] = 9;
// for 1,10,11,12,2,3,4,5,6,7,8,9 
chunkMultipliers[24] = 3;
// for 13,14,15,16,17,18,19,20,21,22,23,24 
chunkMultipliers[25] = 3;
// for 25,26,27,28,29,30,31,32,33,34,35,36 
chunkMultipliers[26] = 3;
// for 1,10,11,12,13,14,15,16,17,18,2,3,4,5,6,7,8,9 
chunkMultipliers[27] = 2;
// for 19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36 
chunkMultipliers[28] = 2;
// for 10,12,14,16,18,2,20,22,24,26,28,30,32,34,36,4,6,8 
chunkMultipliers[29] = 2;
// for 1,11,13,15,17,19,21,23,25,27,29,3,31,33,35,5,7,9 
chunkMultipliers[30] = 2;
// for 1,12,14,16,18,19,21,23,25,27,3,30,32,34,36,5,7,9 
chunkMultipliers[31] = 2;
// for 10,11,13,15,17,2,20,22,24,26,28,29,31,33,35,4,6,8 
chunkMultipliers[32] = 2;
// for 12,15,18,21,24,27,3,30,33,36,6,9 
chunkMultipliers[33] = 3;
// for 11,14,17,2,20,23,26,29,32,35,5,8 
chunkMultipliers[34] = 3;
// for 1,10,13,16,19,22,25,28,31,34,4,7 
chunkMultipliers[35] = 3;
// for 1,2,3 
chunkMultipliers[36] = 12;
// for 4,5,6 
chunkMultipliers[37] = 12;
// for 7,8,9 
chunkMultipliers[38] = 12;
// for 10,11,12 
chunkMultipliers[39] = 12;
// for 13,14,15 
chunkMultipliers[40] = 12;
// for 16,17,18 
chunkMultipliers[41] = 12;
// for 19,20,21 
chunkMultipliers[42] = 12;
// for 22,23,24 
chunkMultipliers[43] = 12;
// for 25,26,27 
chunkMultipliers[44] = 12;
// for 28,29,30 
chunkMultipliers[45] = 12;
// for 31,32,33 
chunkMultipliers[46] = 12;
// for 34,35,36 
chunkMultipliers[47] = 12;
// for 0,1 
chunkMultipliers[48] = 18;
// for 0,2 
chunkMultipliers[49] = 18;
// for 0,3 
chunkMultipliers[50] = 18;
// for 1,2 
chunkMultipliers[51] = 18;
// for 1,4 
chunkMultipliers[52] = 18;
// for 2,3 
chunkMultipliers[53] = 18;
// for 2,5
chunkMultipliers[54] = 18;
// for 3,6 
chunkMultipliers[55] = 18;
// for 4,5 
chunkMultipliers[56] = 18;
// for 4,7 
chunkMultipliers[57] = 18;
// for 5,6 
chunkMultipliers[58] = 18;
// for 5,8 
chunkMultipliers[59] = 18;
// for 6,9 
chunkMultipliers[60] = 18;
// for 7,8 
chunkMultipliers[61] = 18;
// for 7,10 
chunkMultipliers[62] = 18;
// for 8,9 
chunkMultipliers[63] = 18;
// for 8,11 
chunkMultipliers[64] = 18;
// for 9,12 
chunkMultipliers[65] = 18;
// for 10,11 
chunkMultipliers[66] = 18;
// for 10,13 
chunkMultipliers[67] = 18;
// for 11,12 
chunkMultipliers[68] = 18;
// for 11,14 
chunkMultipliers[69] = 18;
// for 12,15 
chunkMultipliers[70] = 18;
// for 13,14 
chunkMultipliers[71] = 18;
// for 13,16 
chunkMultipliers[72] = 18;
// for 14,15 
chunkMultipliers[73] = 18;
// for 14,17 
chunkMultipliers[74] = 18;
// for 15,18 
chunkMultipliers[75] = 18;
// for 16,17 
chunkMultipliers[76] = 18;
// for 16,19 
chunkMultipliers[77] = 18;
// for 17,18 
chunkMultipliers[78] = 18;
// for 17,20 
chunkMultipliers[79] = 18;
// for 18,21 
chunkMultipliers[80] = 18;
// for 19,20 
chunkMultipliers[81] = 18;
// for 19,22 
chunkMultipliers[82] = 18;
// for 20,21 
chunkMultipliers[83] = 18;
// for 20,23 
chunkMultipliers[84] = 18;
// for 21,24 
chunkMultipliers[85] = 18;
// for 22,23 
chunkMultipliers[86] = 18;
// for 22,25 
chunkMultipliers[87] = 18;
// for 23,24 
chunkMultipliers[88] = 18;
// for 23,26 
chunkMultipliers[89] = 18;
// for 24,27 
chunkMultipliers[90] = 18;
// for 25,26 
chunkMultipliers[91] = 18;
// for 25,28 
chunkMultipliers[92] = 18;
// for 26,27 
chunkMultipliers[93] = 18;
// for 26,29 
chunkMultipliers[94] = 18;
// for 27,30 
chunkMultipliers[95] = 18;
// for 28,29 
chunkMultipliers[96] = 18;
// for 28,31 
chunkMultipliers[97] = 18;
// for 29,30 
chunkMultipliers[98] = 18;
// for 29,32 
chunkMultipliers[99] = 18;
// for 30,33 
chunkMultipliers[100] = 18;
// for 31,32 
chunkMultipliers[101] = 18;
// for 31,34 
chunkMultipliers[102] = 18;
// for 32,33 
chunkMultipliers[103] = 18;
// for 32,35 
chunkMultipliers[104] = 18;
// for 33,36 
chunkMultipliers[105] = 18;
// for 34,35 
chunkMultipliers[106] = 18;
// for 35,36
chunkMultipliers[107] = 18;
// for 0
chunkMaps[0] = [0, 1, 48, 49, 50];
// for 1
chunkMaps[1] = [0, 2, 24, 27, 30, 31, 35, 36, 48, 51, 52];
// for 2
chunkMaps[2] = [0, 1, 2, 3, 24, 27, 29, 32, 34, 36, 49, 51, 53, 54];
// for 3
chunkMaps[3] = [1, 3, 24, 27, 30, 31, 33, 36, 50, 53, 55];
// for 4
chunkMaps[4] = [2, 4, 24, 27, 29, 32, 35, 37, 52, 56, 57];
// for 5
chunkMaps[5] = [2, 3, 4, 5, 24, 27, 30, 31, 34, 37, 54, 56, 58, 59];
// for 6
chunkMaps[6] = [3, 5, 24, 27, 29, 32, 33, 37, 55, 58, 60];
// for 7
chunkMaps[7] = [4, 6, 24, 27, 30, 31, 35, 38, 57, 61, 62];
// for 8
chunkMaps[8] = [4, 5, 6, 7, 24, 27, 29, 32, 34, 38, 59, 61, 63, 64];
// for 9
chunkMaps[9] = [5, 7, 24, 27, 30, 31, 33, 38, 60, 63, 65];
// for 10
chunkMaps[10] = [6, 9, 24, 27, 29, 32, 35, 39, 62, 66, 67];
// for 11
chunkMaps[11] = [6, 7, 8, 9, 24, 27, 30, 32, 34, 39, 64, 66, 68, 69];
// for 12
chunkMaps[12] = [7, 8, 24, 27, 29, 31, 33, 39, 65, 68, 70];
// for 13
chunkMaps[13] = [9, 11, 25, 27, 30, 32, 35, 40, 67, 71, 72];
// for 14
chunkMaps[14] = [8, 9, 10, 11, 25, 27, 29, 31, 34, 40, 69, 71, 73, 74];
// for 15
chunkMaps[15] = [8, 10, 25, 27, 30, 32, 33, 40, 70, 73, 75];
// for 16
chunkMaps[16] = [11, 13, 25, 27, 29, 31, 35, 41, 72, 76, 77];
// for 17
chunkMaps[17] = [10, 11, 12, 13, 25, 27, 30, 32, 34, 41, 74, 76, 78, 79];
// for 18
chunkMaps[18] = [10, 12, 25, 27, 29, 31, 33, 41, 75, 78, 80];
// for 19
chunkMaps[19] = [13, 15, 25, 28, 30, 31, 35, 42, 77, 81, 82];
// for 20
chunkMaps[20] = [12, 13, 14, 15, 25, 28, 29, 32, 34, 42, 79, 81, 83, 84];
// for 21
chunkMaps[21] = [12, 14, 25, 28, 30, 31, 33, 42, 80, 83, 85];
// for 22
chunkMaps[22] = [15, 17, 25, 28, 29, 32, 35, 43, 82, 86, 87];
// for 23
chunkMaps[23] = [14, 15, 16, 17, 25, 28, 30, 31, 34, 43, 84, 86, 88, 89];
// for 24
chunkMaps[24] = [14, 16, 25, 28, 29, 32, 33, 43, 85, 88, 90];
// for 25
chunkMaps[25] = [17, 19, 26, 28, 30, 31, 35, 44, 87, 91, 92];
// for 26
chunkMaps[26] = [16, 17, 18, 19, 26, 28, 29, 32, 34, 44, 89, 91, 93, 94];
// for 27
chunkMaps[27] = [16, 18, 26, 28, 30, 31, 33, 44, 90, 93, 95];
// for 28
chunkMaps[28] = [19, 21, 26, 28, 29, 32, 35, 45, 92, 96, 97];
// for 29
chunkMaps[29] = [18, 19, 20, 21, 26, 28, 30, 32, 34, 45, 94, 96, 98, 99];
// for 30
chunkMaps[30] = [18, 20, 26, 28, 29, 31, 33, 45, 95, 98, 100];
// for 31
chunkMaps[31] = [21, 23, 26, 28, 30, 32, 35, 46, 97, 101, 102];
// for 32
chunkMaps[32] = [20, 21, 22, 23, 26, 28, 29, 31, 34, 46, 99, 101, 103, 104];
// for 33
chunkMaps[33] = [20, 22, 26, 28, 30, 32, 33, 46, 100, 103, 105];
// for 34
chunkMaps[34] = [23, 26, 28, 29, 31, 35, 47, 102, 106];
// for 35
chunkMaps[35] = [22, 23, 26, 28, 30, 32, 34, 47, 104, 106, 107];
// for 36
chunkMaps[36] = [22, 26, 28, 29, 31, 33, 47, 105, 107];
  }

  /// @notice the number is used to calculate referrals share
  /// @param _houseEdge winning multipliplier
  function updateHouseEdge(uint64 _houseEdge) external onlyGovernance {
    require(_houseEdge >= 0, "_houseEdge should be greater than or equal to 0");

    houseEdge = _houseEdge;

    emit UpdateHouseEdge(_houseEdge);
  }

  /// @notice updates configuration
  /// @param _configuration because the selections array uint8 max chip could be maximum 256
  function updateConfiguration(Configuration calldata _configuration) external onlyGovernance {
    require(_configuration.maxChip <= 2 ** 8, "maxChip can't be greater");
    require(_configuration.maxChip > 0, "maxChip can't be zero");
    require(_configuration.minChip > 0, "minChip can't be zero");
    require(_configuration.maxCount > 0, "maxCount can't be zero");

    configuration = _configuration;

    emit ConfigurationUpdated(_configuration);
  }

  /// @notice chunk maps are used to easy access to selections which has included the number
  /// @param _index chunk index
  /// @param _map the edges number array for 1 [0,2,24,27,30,31,35]
  function setChunkMaps(uint8 _index, uint8[] calldata _map) external onlyGovernance {
    chunkMaps[_index] = _map;
  }

  /// @notice gets chunk array
  /// @param _index winning multipliplier
  function getChunkMap(uint8 _index) external view returns (uint8[] memory) {
    return chunkMaps[_index];
  }

  /// @notice chunk multipliers are used to get multiplier without making any calculation
  /// @param _index chunk index
  /// @param _multiplier multiplier with no decimals
  function setChunkMultiplier(uint8 _index, uint8 _multiplier) external onlyGovernance {
    chunkMultipliers[_index] = _multiplier;
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
    Game memory game_ = games[_requestId];
    require(game_.player == _msgSender(), "Only player");

    _refundGame(_requestId, game_);
  }

  /// @notice function to refund uncompleted game wagers by team role
  function refundGameByTeam(uint64 _requestId) external nonReentrant onlyTeam {
    Game memory game_ = games[_requestId];
    require(game_.player != address(0), "Game is not created");

    _refundGame(_requestId, game_);
  }

  function _refundGame(uint64 _requestId, Game memory _game) internal {
    require(_game.startTime + refundCooldown < block.timestamp, "Game is not refundable yet");

    vaultManager.refund(_game.token, _game.totalWagerInToken, 0, _game.player);

    delete games[_requestId];
  }

  /// @notice calculates the chips value in token with its decimals
  /// @param _chips amount of chips
  /// @param _token to get decimals
  /// @param _price tokens price which fetched at first tx
  function chip2Token(
    uint256 _chips,
    address _token,
    uint256 _price
  ) public view returns (uint256) {
    return ((_chips * (10 ** (30 + IERC20Metadata(_token).decimals())))) / _price;
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
    Game memory game_ = games[requestId_];

    require(game_.player != address(0), "Game is not created");

    uint8 multiplier_ = singleNumberMultiplier;
    uint8 chunkId_;
    uint8 outcome_;
    uint8 wager_;
    uint8[] memory chunkMaps_;
    uint8[108] memory chunkMultipliers_ = chunkMultipliers;
    uint32 payout_;

    unchecked {
      for (uint8 i = 0; i < game_.count; ++i) {
        // to get outcome modded 37 because the game has 37 numbers included 0
        outcome_ = uint8(_randoms[i] % 37);

        // if player directly wagered to the outcome gives the winning over it
        if (game_.selections[outcome_] > 0) {
          payout_ += uint32(game_.selections[outcome_]) * multiplier_;
        }

        // than checks if the edges which includes the outcome has wagered
        chunkMaps_ = chunkMaps[outcome_];
        for (uint8 x = 0; x < chunkMaps_.length; ++x) {
          chunkId_ = chunkMaps_[x];
          wager_ = game_.selections[37 + chunkId_];

          // if has gives adds the winning to payout
          if (wager_ > 0) {
            payout_ += uint32(wager_) * chunkMultipliers_[chunkId_];
          }
        }
      }
    }

    uint256 totalPayoutInToken_;

    /// @notice sets referral reward if player has referee
    vaultManager.setReferralReward(
      game_.token,
      game_.player,
      game_.totalWagerInToken,
      getHouseEdge()
    );
    vaultManager.mintVestedWINR(game_.token, game_.totalWagerInToken, game_.player);

    /// @notice calculates the loss of user if its not zero transfers to Vault
    if (payout_ == 0) {
      vaultManager.payin(game_.token, game_.totalWagerInToken);
    } else {
      totalPayoutInToken_ = chip2Token(payout_, game_.token, game_.price);
      vaultManager.payout(game_.token, game_.player, game_.totalWagerInToken, totalPayoutInToken_);
    }

    emit Settled(game_.player, requestId_, totalPayoutInToken_, _randoms);

    delete games[requestId_];
  }

  /// @notice starts the game and triggers randomizer
  /// @param _selections player's selections array [3] => max 256 means for 3rd number 256 wager
  /// @param _count multiple game count
  /// @param _token input and output token
  function bet(
    uint8[145] calldata _selections,
    uint8 _count,
    address _token
  ) external whenNotPaused nonReentrant {
    Configuration memory configuration_ = configuration;

    require(_count > 0 && _count <= configuration_.maxCount, "GAME: Count is invalid!");

    uint8 wager_;
    uint16 totalWager_;
    address player_ = _msgSender();
    uint64 requestId_ = uint64(_requestRandom(_count));
    uint128 price_ = uint128(vaultManager.getPrice(_token)); // gets price and keep it in object to make calculation

    unchecked {
      for (uint8 i = 0; i < 145; ++i) {
        wager_ = _selections[i];

        if (wager_ > 0) {
          require(wager_ >= configuration_.minChip, "GAME: Wager too low");
          require(wager_ <= configuration_.maxChip, "GAME: Wager too high");

          totalWager_ += wager_;
        }
      }
    }

    require(totalWager_ > 0, "At least 1 number should be selected");
    // Total wager should not be greater than platform's max wager
    require(totalWager_ <= vaultManager.getMaxWager() / 10 ** 30, "GAME: Wager too high");
    
    uint256 value_ = _count * chip2Token(totalWager_, _token, price_);
    require(value_ <= type(uint128).max, "GAME: value is too high");
       
    uint128 totalWagerInToken_ = uint128(value_);

    /// @notice escrows total wager to Vault Manager
    vaultManager.escrow(_token, player_, totalWagerInToken_);

    // Creating game object
    games[requestId_] = Game(
      _selections,
      _count,
      _token,
      player_,
      uint64(block.timestamp),
      totalWagerInToken_,
      price_
    );

    emit Created(_selections, _count, _token, player_, requestId_, price_);
  }
}

