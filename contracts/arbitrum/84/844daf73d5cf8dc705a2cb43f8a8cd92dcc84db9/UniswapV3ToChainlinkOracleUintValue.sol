// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {UniswapV3OracleUintValue} from "./UniswapV3OracleUintValue.sol";
import {AggregatorInterface, IUintValue, IUniswapV3Oracle, IUniswapV3ToChainlinkOracleUintValue} from "./IUniswapV3ToChainlinkOracleUintValue.sol";
import {SafeCast} from "./SafeCast.sol";

contract UniswapV3ToChainlinkOracleUintValue is
  IUniswapV3ToChainlinkOracleUintValue,
  UniswapV3OracleUintValue
{
  AggregatorInterface internal immutable _chainlinkOracle;
  address internal immutable _chainlinkBaseToken;
  address internal immutable _chainlinkQuoteToken;
  uint256 internal immutable _uniswapQuoteTokenUnit;
  uint256 internal immutable _chainlinkBaseTokenUnit;

  constructor(
    IUniswapV3Oracle uniswapOracle,
    address uniswapBaseToken,
    address uniswapQuoteToken,
    AggregatorInterface chainlinkOracle,
    address chainlinkBaseToken,
    address chainlinkQuoteToken,
    uint256 uniswapQuoteTokenDecimals,
    uint256 chainlinkBaseTokenDecimals
  )
    UniswapV3OracleUintValue(
      uniswapOracle,
      uniswapBaseToken,
      uniswapQuoteToken
    )
  {
    if (
      uniswapQuoteToken != chainlinkBaseToken &&
      uniswapQuoteToken != chainlinkQuoteToken
    ) revert();
    _chainlinkOracle = chainlinkOracle;
    _chainlinkBaseToken = chainlinkBaseToken;
    _chainlinkQuoteToken = chainlinkQuoteToken;
    _uniswapQuoteTokenUnit = 10**uniswapQuoteTokenDecimals;
    _chainlinkBaseTokenUnit = 10**chainlinkBaseTokenDecimals;
  }

  function get()
    external
    view
    override(IUintValue, UniswapV3OracleUintValue)
    returns (uint256 finalOutputAmount)
  {
    (uint256 uniswapQuoteAmount, ) = _uniswapOracle
      .quoteAllAvailablePoolsWithTimePeriod(
        _baseAmount,
        _uniswapBaseToken,
        _uniswapQuoteToken,
        _observationPeriod
      );
    uint256 chainlinkQuoteAmount = SafeCast.toUint256(
      _chainlinkOracle.latestAnswer()
    );
    finalOutputAmount = (_uniswapQuoteToken == _chainlinkQuoteToken) // final output token = chainlink base token
      ? (uniswapQuoteAmount * _chainlinkBaseTokenUnit) / chainlinkQuoteAmount // final output token = chainlink quote token
      : (uniswapQuoteAmount * chainlinkQuoteAmount) / _uniswapQuoteTokenUnit;
  }

  function getChainlinkOracle()
    external
    view
    override
    returns (AggregatorInterface)
  {
    return _chainlinkOracle;
  }

  function getChainlinkBaseToken() external view override returns (address) {
    return _chainlinkBaseToken;
  }

  function getChainlinkQuoteToken() external view override returns (address) {
    return _chainlinkQuoteToken;
  }

  function getFinalQuoteToken() external view override returns (address) {
    return
      (_uniswapQuoteToken == _chainlinkQuoteToken)
        ? _chainlinkBaseToken
        : _chainlinkQuoteToken;
  }
}

