// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "./Liquidation.sol";

contract CVIUSDCLiquidation is Liquidation {
  constructor(uint16 _maxCVIValue) Liquidation(_maxCVIValue) {}
}

contract CVIUSDCLiquidation2X is Liquidation {
  constructor(uint16 _maxCVIValue) Liquidation(_maxCVIValue) {}
}
