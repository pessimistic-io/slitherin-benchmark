// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryQuoterBorrowGivenPrincipal} from "./ITimeswapV2PeripheryQuoterBorrowGivenPrincipal.sol";

import {TimeswapV2PeripheryNoDexQuoterBorrowGivenPrincipalParam} from "./QuoterParam.sol";

import {IMulticall} from "./IMulticall.sol";

/// @title An interface for TS-V2 Periphery NoDex Borrow Given Pricipal.
interface ITimeswapV2PeripheryNoDexQuoterBorrowGivenPrincipal is
  ITimeswapV2PeripheryQuoterBorrowGivenPrincipal,
  IMulticall
{
  /// @dev The borrow given principal function.
  /// @param param Borrow given principal param.
  /// @return positionAmount
  function borrowGivenPrincipal(
    TimeswapV2PeripheryNoDexQuoterBorrowGivenPrincipalParam calldata param,
    uint96 durationForward
  ) external returns (uint256 positionAmount, uint160 timeswapV2SqrtInterestRateAfter);
}

