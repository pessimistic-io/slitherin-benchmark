// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IUintValue, IUniswapV3Oracle, IUniswapV3OracleUintValue} from "./IUniswapV3OracleUintValue.sol";
import {AggregatorInterface} from "./AggregatorInterface.sol";

interface IUniswapV3ToChainlinkOracleUintValue is IUniswapV3OracleUintValue {
  function getChainlinkOracle() external view returns (AggregatorInterface);

  function getChainlinkBaseToken() external view returns (address);

  function getChainlinkQuoteToken() external view returns (address);

  function getFinalQuoteToken() external view returns (address);
}

