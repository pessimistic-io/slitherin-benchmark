// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IOreoV3PoolImmutables.sol";
import "./IOreoV3PoolState.sol";
import "./IOreoV3PoolDerivedState.sol";
import "./IOreoV3PoolActions.sol";
import "./IOreoV3PoolOwnerActions.sol";
import "./IOreoV3PoolEvents.sol";

/// @title The interface for a OreoSwap V3 Pool
/// @notice A OreoSwap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IOreoV3Pool is
    IOreoV3PoolImmutables,
    IOreoV3PoolState,
    IOreoV3PoolDerivedState,
    IOreoV3PoolActions,
    IOreoV3PoolOwnerActions,
    IOreoV3PoolEvents
{

}

