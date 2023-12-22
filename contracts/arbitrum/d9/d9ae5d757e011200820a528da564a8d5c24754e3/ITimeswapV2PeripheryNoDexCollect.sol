// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryCollect} from "./ITimeswapV2PeripheryCollect.sol";

import {INativeWithdraws} from "./INativeWithdraws.sol";
import {IMulticall} from "./IMulticall.sol";

import {TimeswapV2PeripheryNoDexCollectParam} from "./structs_Param.sol";

/// @title An interface for TS-V2 Periphery No Dex Collect.
interface ITimeswapV2PeripheryNoDexCollect is ITimeswapV2PeripheryCollect, INativeWithdraws, IMulticall {
  event Collect(
    address indexed token0,
    address indexed token1,
    uint256 strike,
    uint256 indexed maturity,
    address to,
    uint256 token0Amount,
    uint256 token1Amount,
    uint256 shortFees,
    uint256 shortReturned,
    uint256 excessShortAmount
  );

  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  /// @dev The collect function.
  /// @param param Collect param.
  /// @return token0Amount
  /// @return token1Amount
  function collect(
    TimeswapV2PeripheryNoDexCollectParam calldata param
  ) external returns (uint256 token0Amount, uint256 token1Amount);
}

