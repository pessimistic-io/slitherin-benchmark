// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {UniswapV3OracleUintValue} from "./UniswapV3OracleUintValue.sol";
import {IPriceOracle, IUintValue, IUniswapV3Oracle, IUniswapV3ToBalancerV2OracleUintValue} from "./IUniswapV3ToBalancerV2OracleUintValue.sol";

contract UniswapV3ToBalancerV2OracleUintValue is
  IUniswapV3ToBalancerV2OracleUintValue,
  UniswapV3OracleUintValue
{
  /**
   * Unlike with UniswapV3, we are not using an intermediary pool
   * aggregator contract for Balancer (Balancer doesn't have on-chain
   * pool routing anyway). Instead, we provide the Balancer pool directly
   * and thus don't need to store a token.
   */
  IPriceOracle internal immutable _balancerOracle;
  uint256 internal immutable _uniswapQuoteTokenUnit;

  constructor(
    IUniswapV3Oracle uniswapOracle,
    address baseToken,
    address uniswapQuoteToken,
    IPriceOracle balancerOracle,
    uint256 uniswapQuoteTokenDecimals
  ) UniswapV3OracleUintValue(uniswapOracle, baseToken, uniswapQuoteToken) {
    _balancerOracle = balancerOracle;
    _uniswapQuoteTokenUnit = 10**uniswapQuoteTokenDecimals;
  }

  function get()
    external
    view
    override(IUintValue, UniswapV3OracleUintValue)
    returns (uint256 balancerQuoteAmount)
  {
    (uint256 uniswapQuoteAmount, ) = _uniswapOracle
      .quoteAllAvailablePoolsWithTimePeriod(
        _baseAmount,
        _baseToken,
        _uniswapQuoteToken,
        _observationPeriod
      );
    IPriceOracle.OracleAverageQuery[]
      memory balancerQuoteParams = new IPriceOracle.OracleAverageQuery[](1);
    balancerQuoteParams[0] = IPriceOracle.OracleAverageQuery(
      // This specifies that we want the price expressed as token1 in terms of token0.
      IPriceOracle.Variable.PAIR_PRICE,
      _observationPeriod,
      /**
       * 0 seconds ago is now, and we want to look back `_observationPeriod`
       * seconds in the past.
       */
      0
    );
    uint256[] memory balancerQuoteAmounts = _balancerOracle
      .getTimeWeightedAverage(balancerQuoteParams);
    /**
     * Balancer quote is 1 unit of the Uniswap quote token in terms of the
     * Balancer quote token. So we multiply by the quote, then divide by the
     * Uniswap quote token's unit.
     */
    balancerQuoteAmount =
      (uniswapQuoteAmount * balancerQuoteAmounts[0]) /
      _uniswapQuoteTokenUnit;
  }

  function getBalancerOracle() external view override returns (IPriceOracle) {
    return _balancerOracle;
  }
}

