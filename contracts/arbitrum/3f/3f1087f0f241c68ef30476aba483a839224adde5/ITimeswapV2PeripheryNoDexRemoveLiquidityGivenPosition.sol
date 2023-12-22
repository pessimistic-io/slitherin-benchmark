// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryRemoveLiquidityGivenPosition} from "./ITimeswapV2PeripheryRemoveLiquidityGivenPosition.sol";
import {FeesAndReturnedDelta, ExcessDelta} from "./contracts_structs_Param.sol";

import {INativeWithdraws} from "./INativeWithdraws.sol";
import {IMulticall} from "./IMulticall.sol";

import {TimeswapV2PeripheryNoDexRemoveLiquidityGivenPositionParam} from "./structs_Param.sol";

/// @title An interface for TS-V2 Periphery NoDex RemoveLiquidity.
interface ITimeswapV2PeripheryNoDexRemoveLiquidityGivenPosition is
  ITimeswapV2PeripheryRemoveLiquidityGivenPosition,
  INativeWithdraws,
  IMulticall
{
  event RemoveLiquidityGivenPosition(
    address indexed token0,
    address indexed token1,
    uint256 strike,
    uint256 indexed maturity,
    address from,
    address tokenTo,
    uint256 token0Amount,
    uint256 token1Amount,
    uint256 liquidityAmount,
    FeesAndReturnedDelta feesAndReturnedDelta,
    ExcessDelta excessDelta
  );

  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  error MinSqrtInterestRateReached(uint160 sqrtInterestRate, uint160 minSqrtInterestRate);

  error MaxSqrtInterestRateReached(uint160 sqrtInterestRate, uint160 maxSqrtInterestRate);

  /// @dev The remove liquidity function.
  /// @param param Remove liquidity param.
  /// @return token0Amount
  /// @return token1Amount
  /// @return feesAndReturnedDelta
  /// @return excessDelta
  function removeLiquidityGivenPosition(
    TimeswapV2PeripheryNoDexRemoveLiquidityGivenPositionParam calldata param
  )
    external
    returns (
      uint256 token0Amount,
      uint256 token1Amount,
      FeesAndReturnedDelta memory feesAndReturnedDelta,
      ExcessDelta memory excessDelta
    );
}

