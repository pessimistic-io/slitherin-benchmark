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

  /*==================================================== State Variables ====================================================*/

  /// @notice used to calculate precise decimals
  uint256 public constant PRECISION = 1e18;
  /// @notice used to calculate Referral Rewards
  uint32 public constant BASIS_POINTS = 1e4;
  /// @notice Vault manager address
  IVaultManager public vaultManager;

  mapping(address => uint256) private decimalsOfToken;

  /*==================================================== Functions ===========================================================*/

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
      emit LuckyStrike(msg.sender, wonAmount_, true /** true */);
      return true;
    } else {
      emit LuckyStrike(msg.sender, 0, false /** flase */);
      return false;
    }
  }

  function _computeDollarValue(
    address _token,
    uint256 _wager
  ) internal returns (uint256 _wagerInDollar) {
    // todo check if we can make this one view (and if that helps for gas usage)
    unchecked {
      _wagerInDollar = ((_wager * vaultManager.getPrice(_token))) / (10 ** _getDecimals(_token));
    }
  }

  function _getDecimals(address _token) internal returns (uint256 decimals_) {
    if (decimalsOfToken[_token] == 0) {
      decimalsOfToken[_token] = IERC20Metadata(_token).decimals();
      return decimalsOfToken[_token];
    } else {
      return decimalsOfToken[_token];
    }
  }
}

