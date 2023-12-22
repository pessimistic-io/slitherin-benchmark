// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {Error} from "./Error.sol";

import {ITimeswapV2OptionFactory} from "./ITimeswapV2OptionFactory.sol";
import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {TimeswapV2OptionCollectParam} from "./structs_Param.sol";

import {TimeswapV2OptionCollect} from "./enums_Transaction.sol";

import {ITimeswapV2PoolFactory} from "./ITimeswapV2PoolFactory.sol";
import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {TimeswapV2PoolCollectParam} from "./v2-pool_contracts_structs_Param.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {TimeswapV2LiquidityTokenCollectParam} from "./v2-token_contracts_structs_Param.sol";

import {ITimeswapV2LiquidityToken} from "./ITimeswapV2LiquidityToken.sol";

import {ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity} from "./ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity.sol";

import {TimeswapV2PeripheryCollectTransactionFeesAfterMaturityParam} from "./structs_Param.sol";

abstract contract TimeswapV2PeripheryCollectTransactionFeesAfterMaturity is
  ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity
{
  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity
  address public immutable override poolFactory;
  /// @inheritdoc ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity
  address public immutable override tokens;
  /// @inheritdoc ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity
  address public immutable override liquidityTokens;

  /* ===== INIT ===== */

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenLiquidityTokens
  ) {
    optionFactory = chosenOptionFactory;
    poolFactory = chosenPoolFactory;
    tokens = chosenTokens;
    liquidityTokens = chosenLiquidityTokens;
  }

  function collectTransactionFeesAfterMaturity(
    TimeswapV2PeripheryCollectTransactionFeesAfterMaturityParam memory param
  ) internal returns (uint256 token0Amount, uint256 token1Amount) {
    if (param.maturity > block.timestamp) Error.stillActive(param.maturity, uint96(block.timestamp));

    (address optionPair, address poolPair) = PoolFactoryLibrary.getWithCheck(
      optionFactory,
      poolFactory,
      param.token0,
      param.token1
    );

    ITimeswapV2LiquidityToken(liquidityTokens).collect(
      TimeswapV2LiquidityTokenCollectParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        to: address(this),
        long0FeesDesired: 0,
        long1FeesDesired: 0,
        shortFeesDesired: param.shortRequested,
        data: bytes("")
      })
    );

    (, , uint256 shortAmount) = ITimeswapV2Pool(poolPair).collectTransactionFees(
      TimeswapV2PoolCollectParam({
        strike: param.strike,
        maturity: param.maturity,
        long0To: address(this),
        long1To: address(this),
        shortTo: address(this),
        long0Requested: 0,
        long1Requested: 0,
        shortRequested: param.shortRequested
      })
    );

    (token0Amount, token1Amount, , ) = ITimeswapV2Option(optionPair).collect(
      TimeswapV2OptionCollectParam({
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.token0To,
        token1To: param.token1To,
        transaction: TimeswapV2OptionCollect.GivenShort,
        amount: shortAmount,
        data: bytes("")
      })
    );
  }
}

