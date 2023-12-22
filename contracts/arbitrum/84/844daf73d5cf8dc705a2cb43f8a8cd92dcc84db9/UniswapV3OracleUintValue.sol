// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {SafeOwnable} from "./SafeOwnable.sol";
import {IUniswapV3Oracle, IUniswapV3OracleUintValue} from "./IUniswapV3OracleUintValue.sol";

contract UniswapV3OracleUintValue is IUniswapV3OracleUintValue, SafeOwnable {
  IUniswapV3Oracle internal immutable _uniswapOracle;
  address internal immutable _uniswapBaseToken;
  address internal immutable _uniswapQuoteToken;
  uint32 internal _observationPeriod;
  uint128 internal _baseAmount;

  constructor(
    IUniswapV3Oracle uniswapOracle,
    address uniswapBaseToken,
    address uniswapQuoteToken
  ) {
    _uniswapOracle = uniswapOracle;
    _uniswapBaseToken = uniswapBaseToken;
    _uniswapQuoteToken = uniswapQuoteToken;
  }

  function setObservationPeriod(uint32 observationPeriod)
    external
    override
    onlyOwner
  {
    _observationPeriod = observationPeriod;
    emit ObservationPeriodChange(observationPeriod);
  }

  function setBaseAmount(uint128 baseAmount) external override onlyOwner {
    _baseAmount = baseAmount;
    emit BaseAmountChange(baseAmount);
  }

  function get() external view virtual override returns (uint256 quoteAmount) {
    (quoteAmount, ) = _uniswapOracle.quoteAllAvailablePoolsWithTimePeriod(
      _baseAmount,
      _uniswapBaseToken,
      _uniswapQuoteToken,
      _observationPeriod
    );
  }

  function getUniswapOracle()
    external
    view
    override
    returns (IUniswapV3Oracle)
  {
    return _uniswapOracle;
  }

  function getUniswapBaseToken() external view override returns (address) {
    return _uniswapBaseToken;
  }

  function getUniswapQuoteToken() external view override returns (address) {
    return _uniswapQuoteToken;
  }

  function getObservationPeriod() external view override returns (uint32) {
    return _observationPeriod;
  }

  function getBaseAmount() external view override returns (uint128) {
    return _baseAmount;
  }
}

