// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IUniswapV3PoolImmutables} from "./IUniswapV3PoolImmutables.sol";
import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";
import {IUniswapV3PoolActions} from "./IUniswapV3PoolActions.sol";

/// @title The interface for a Uniswap V3 Pool
/// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
// solhint-disable-next-line no-empty-blocks
interface IUniswapV3Pool is 
  IUniswapV3PoolImmutables, 
  IUniswapV3PoolState,
  IUniswapV3PoolActions
{
    
}

