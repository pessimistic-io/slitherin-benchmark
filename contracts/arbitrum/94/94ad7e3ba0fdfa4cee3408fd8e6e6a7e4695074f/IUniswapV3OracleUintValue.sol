// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IUintValue} from "./IUintValue.sol";
import {IUniswapV3Oracle} from "./IUniswapV3Oracle.sol";

interface IUniswapV3OracleUintValue is IUintValue {
  event BaseAmountChange(uint128 amount);
  event ObservationPeriodChange(uint32 period);

  function setObservationPeriod(uint32 observationPeriod) external;

  function setBaseAmount(uint128 amount) external;

  function getUniswapOracle() external view returns (IUniswapV3Oracle);

  function getBaseToken() external view returns (address);

  function getUniswapQuoteToken() external view returns (address);

  function getObservationPeriod() external view returns (uint32);

  function getBaseAmount() external view returns (uint128);
}

