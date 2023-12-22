// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IVolatilityOracle } from "./IVolatilityOracle.sol";

contract MockVolatilityOracle {
  uint256 public volatility = 150;

  function updateVolatility(uint256 _volatility) external returns (bool) {
    volatility = _volatility;
    return true;
  }

  function getVolatility() public view returns (uint256) {
    return volatility;
  }

  function getVolatility(uint256) public view returns (uint256) {
    return volatility;
  }
}

