// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import { FixedPointMathLib } from "./FixedPointMathLib.sol";

abstract contract TimeBonus {
  using FixedPointMathLib for uint256;

  uint256 public timeForBonus; // Time in seconds to get a 100% bonus
  uint256 public maxBonusBps; // Maximum bonus percentage

  uint256 public constant MAX_BONUS_BPS = 10_000; // denominator represents 100.00%

  function getMaxBonusBpsDenom() public pure returns (uint256 maxBps) {
    return MAX_BONUS_BPS;
  }

  constructor(uint256 _timeForBonus, uint256 _maxBonusBps) {
    timeForBonus = _timeForBonus;
    maxBonusBps = _maxBonusBps;
  }

  modifier onlyAuthorized() {
    require(_hasTimeBonusAuthority(), "Not authorized");
    _;
  }

  function setTimeForBonus(uint256 _timeForBonus) public onlyAuthorized {
    timeForBonus = _timeForBonus;
  }

  function setMaxBonusPercent(uint256 _maxBonusBps) public onlyAuthorized {
    maxBonusBps = _maxBonusBps;
  }

  function getBonusPercent(uint256 deltaTime) public view returns (uint256) {
    uint256 bonusBps = deltaTime.mulDivDown(MAX_BONUS_BPS, timeForBonus);
    if (bonusBps > maxBonusBps) {
      bonusBps = maxBonusBps;
    }
    return bonusBps;
  }

  // =============================================================
  //                    INTERNAL HOOKS LOGIC
  // =============================================================
  function _hasTimeBonusAuthority() internal view virtual returns (bool);
}

