// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IV3PoolImmutables} from "./IV3PoolImmutables.sol";
import {IV3PoolState} from "./IV3PoolState.sol";
import {IV3PoolDerivedState} from "./IV3PoolDerivedState.sol";
import {IV3PoolActions} from "./IV3PoolActions.sol";
import {IV3PoolOwnerActions} from "./IV3PoolOwnerActions.sol";
import {IV3PoolErrors} from "./IV3PoolErrors.sol";
import {IV3PoolEvents} from "./IV3PoolEvents.sol";

import {IV3PoolOptions} from "./IV3PoolOptions.sol";

/// @title The interface for a  V3 Pool
/// @notice A  pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IV3Pool is
    IV3PoolImmutables,
    IV3PoolState,
    IV3PoolDerivedState,
    IV3PoolActions,
    IV3PoolOwnerActions,
    IV3PoolErrors,
    IV3PoolEvents,
    IV3PoolOptions
{
    function fee() external view returns (uint24);

    function transferFromPool(
        address token,
        address to,
        uint256 amount
    ) external;

    function slots0(
        bytes32 optionPoolKeyHash // the current price
    ) external view returns (uint160 sqrtPriceX96, int24 tick, bool unlocked);

    function updatePoolBalances(
        bytes32 optionPoolKeyHash,
        int256 token0Delta,
        int256 token1Delta
    ) external;
}

