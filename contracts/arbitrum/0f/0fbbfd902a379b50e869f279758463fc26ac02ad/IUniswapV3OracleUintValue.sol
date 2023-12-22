// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IUintValue.sol";
import "./IUniswapV3Oracle.sol";

interface IUniswapV3OracleUintValue is IUintValue {
  event ObservationPeriodChange(uint32 period);

  event BaseAmountChange(uint128 amount);

  function setObservationPeriod(uint32 observationPeriod) external;

  function setBaseAmount(uint128 amount) external;

  function getOracle() external view returns (IUniswapV3Oracle);

  function getBaseToken() external view returns (address);

  function getQuoteToken() external view returns (address);

  function getObservationPeriod() external view returns (uint32);

  function getBaseAmount() external view returns (uint128);
}

