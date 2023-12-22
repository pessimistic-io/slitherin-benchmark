// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IUintValue, IUniswapV3Oracle, IUniswapV3OracleUintValue} from "./IUniswapV3OracleUintValue.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

interface IUniswapV3ToBalancerV2OracleUintValue is IUniswapV3OracleUintValue {
  function getBalancerOracle() external view returns (IPriceOracle);
}

