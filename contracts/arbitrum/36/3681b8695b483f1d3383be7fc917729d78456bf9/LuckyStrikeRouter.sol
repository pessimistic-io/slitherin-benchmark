// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ILuckyStrikeMaster.sol";

abstract contract LuckyStrikeRouter {
  event LuckyStrike(address indexed player, uint256 wonAmount, bool won);

  ILuckyStrikeMaster public masterStrike;

  function _hasLuckyStrikeCheck(
    uint256 _randomness,
    uint256 _usdWager
  ) internal view returns (bool hasWon_) {
    hasWon_ = masterStrike.hasLuckyStrike(_randomness, _usdWager);
  }

  function _processLuckyStrike(address _player) internal returns (uint256 wonAmount_) {
    wonAmount_ = masterStrike.processLuckyStrike(_player);
    emit LuckyStrike(_player, wonAmount_, wonAmount_ > 0);
  }
}

