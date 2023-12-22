// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IMallowV3PoolImmutables.sol";
import "./IMallowV3PoolState.sol";
import "./IMallowV3PoolDerivedState.sol";
import "./IMallowV3PoolActions.sol";
import "./IMallowV3PoolOwnerActions.sol";
import "./IMallowV3PoolEvents.sol";

/// @title The interface for a MallowSwap V3 Pool
/// @notice A MallowSwap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IMallowV3Pool is
    IMallowV3PoolImmutables,
    IMallowV3PoolState,
    IMallowV3PoolDerivedState,
    IMallowV3PoolActions,
    IMallowV3PoolOwnerActions,
    IMallowV3PoolEvents
{

}

