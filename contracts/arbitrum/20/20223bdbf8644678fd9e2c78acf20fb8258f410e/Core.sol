// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./IERC20Metadata.sol";
import "./LuckyStrikeRouter.sol";
import "./IVaultManager.sol";
import "./RandomizerConsumer.sol";
import "./Access.sol";
import "./Number.sol";

abstract contract Core is
  Pausable,
  Access,
  ReentrancyGuard,
  NumberHelper,
  RandomizerConsumer,
  LuckyStrikeRouter
{
  /*==================================================== Events ==========================================================*/

  event VaultManagerChange(address vaultManager);
  event LuckyStrikeMasterChange(address masterStrike);

  /*==================================================== Modifiers ==========================================================*/

  modifier isWagerAcceptable(address _token, uint256 _wager) {
    uint256 dollarValue_ = _computeDollarValue(_token, _wager);
    require(dollarValue_ >= vaultManager.getMinWager(address(this)), "GAME: Wager too low");
    require(dollarValue_ <= vaultManager.getMaxWager(), "GAME: Wager too high");
    _;
  }

  /// @notice used to calculate precise decimals
  uint256 public constant PRECISION = 1e18;
  /// @notice used to calculate Referral Rewards
  uint32 public constant BASIS_POINTS = 1e4;
  /// @notice Vault manager address
  IVaultManager public vaultManager;

  uint16 public constant ALPHA = 999; // 0.999

  int24 public constant SIGMA_1 = 100; // 0.1
  int24 public constant MEAN_1 = 600; // 0.6

  int24 public constant SIGMA_2 = 10000; // 10
  int24 public constant MEAN_2 = 100000; // 100

  mapping(address => uint256) private decimalsOfToken;

  constructor(IRandomizerRouter _router) RandomizerConsumer(_router) {}

  function setVaultManager(IVaultManager _vaultManager) external onlyGovernance {
    vaultManager = _vaultManager;

    emit VaultManagerChange(address(_vaultManager));
  }

  function setLuckyStrikeMaster(ILuckyStrikeMaster _masterStrike) external onlyGovernance {
    masterStrike = _masterStrike;

    emit LuckyStrikeMasterChange(address(_masterStrike));
  }

  function pause() external onlyTeam {
    _pause();
  }

  function unpause() external onlyTeam {
    _unpause();
  }

  /**
   * @notice internal function that checks in the player has won the lucky strike jackpot
   * @param _randomness random number from the randomizer / vrf
   * @param _player address of the player that has wagered
   * @param _token address of the token the player has wagered
   * @param _usedWager amount of the token the player has wagered
   */
  function _hasLuckyStrike(
    uint256 _randomness,
    address _player,
    address _token,
    uint256 _usedWager
  ) internal returns (bool hasWon_) {
    if (_hasLuckyStrikeCheck(_randomness, _computeDollarValue(_token, _usedWager))) {
      uint256 wonAmount_ = _processLuckyStrike(_player);
      emit LuckyStrike(_player, wonAmount_, true /** true */);
      return true;
    } else {
      emit LuckyStrike(_player, 0, false /** flase */);
      return false;
    }
  }

  /// @notice function to compute jackpot multiplier
  function _computeMultiplier(uint256 _random) internal pure returns (uint256) {
    int256 _sumOfRandoms = int256(_generateRandom(_random)) - 6000;
    _random = (_random % 1000) + 1;

    uint256 multiplier;
    unchecked {
      if (_random >= ALPHA) {
        multiplier = uint256((SIGMA_2 * _sumOfRandoms) / 1e3 + MEAN_2);
      } else {
        multiplier = uint256((SIGMA_1 * _sumOfRandoms) / 1e3 + MEAN_1);
      }
    }

    return _clamp(multiplier, 100, 100000);
  }

  function _clamp(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// @param _random random number that comes from vrf
  /// @notice function to generate 12 random numbers and sum them up
  function _generateRandom(uint256 _random) internal pure returns (uint256 sumOfRandoms_) {
    unchecked {
      uint256 factor = 1;
      for (uint256 i = 0; i < 12; ++i) {
        sumOfRandoms_ += (_random / factor) % 1000;
        factor *= 1000;
      }
    }
    return sumOfRandoms_;
  }

  function _computeDollarValue(
    address _token,
    uint256 _wager
  ) internal returns (uint256 _wagerInDollar) {
    unchecked {
      _wagerInDollar = ((_wager * vaultManager.getPrice(_token))) / (10 ** _getDecimals(_token));
    }
  }

  function _getDecimals(address _token) internal returns (uint256) {
    uint256 decimals_ = decimalsOfToken[_token];
    if (decimals_ == 0) {
      decimalsOfToken[_token] = IERC20Metadata(_token).decimals();
      return decimalsOfToken[_token];
    } else {
      return decimals_;
    }
  }
}

