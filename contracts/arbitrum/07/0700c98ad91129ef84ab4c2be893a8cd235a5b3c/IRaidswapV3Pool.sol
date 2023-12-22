// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IRaidswapV3PoolImmutables.sol";
import "./IRaidswapV3PoolState.sol";
import "./IRaidswapV3PoolDerivedState.sol";
import "./IRaidswapV3PoolActions.sol";
import "./IRaidswapV3PoolOwnerActions.sol";
import "./IRaidswapV3PoolEvents.sol";

/// @title The interface for a Raidswap V3 Pool
/// @notice A Raidswap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IRaidswapV3Pool is
    IRaidswapV3PoolImmutables,
    IRaidswapV3PoolState,
    IRaidswapV3PoolDerivedState,
    IRaidswapV3PoolActions,
    IRaidswapV3PoolOwnerActions,
    IRaidswapV3PoolEvents
{

}

