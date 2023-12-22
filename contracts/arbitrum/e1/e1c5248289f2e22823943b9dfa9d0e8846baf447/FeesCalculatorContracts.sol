// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "./FeesCalculator.sol";

contract CVIUSDCFeesCalculator is FeesCalculator {
  constructor(
    ICVIOracle _cviOracle,
    uint16 _maxCVIValue,
    uint8 _oracleLeverage
  ) FeesCalculator(_cviOracle, _maxCVIValue, _oracleLeverage) {}
}

contract CVIUSDCFeesCalculator2X is FeesCalculator {
  constructor(
    ICVIOracle _cviOracle,
    uint16 _maxCVIValue,
    uint8 _oracleLeverage
  ) FeesCalculator(_cviOracle, _maxCVIValue, _oracleLeverage) {}
}

