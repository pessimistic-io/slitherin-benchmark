// SPDX-License-Identifier: MIT

/***
 *      ______             _______   __
 *     /      \           |       \ |  \
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *
 *
 *
 */

pragma solidity ^0.8.4;

import { IAlgebraPool } from "./IAlgebraPool.sol";
import {Address} from "./Address.sol";

/**
 * @title SafeAlgebraPool
 * @dev Wrappers around IAlgebraPool operations that throw on failure
 * (when the token contract returns false).
 * Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeAlgebraPool for
 * IAlgebraPool;` statement to your contract, which allows you
 * to call the safe operations as `token.observe(...)`, etc.
 */
library SafeAlgebraPool {
    using Address for address;

    function safeTicks(IAlgebraPool pool, int24 tick)
        internal
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {
        bytes memory returndata =
            address(pool).functionStaticCall(
                abi.encodeWithSelector(pool.ticks.selector, tick),
                "SafeAlgebraPool: low-level call failed"
            );
        return
            abi.decode(
                returndata,
                (
                    uint128,
                    int128,
                    uint256,
                    uint256,
                    int56,
                    uint160,
                    uint32,
                    bool
                )
            );
    }

    function safePositions(IAlgebraPool pool, bytes32 key)
        internal
        view
        returns (
            uint128 _liquidity,
            uint32 _lastLiquidityAddTimestamp,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        bytes memory returndata =
            address(pool).functionStaticCall(
                abi.encodeWithSelector(pool.positions.selector, key),
                "SafeAlgebraPool: low-level call failed"
            );
        return
            abi.decode(
                returndata,
                (uint128, uint32, uint256, uint256, uint128, uint128)
            );
    }

    function safeState(IAlgebraPool pool)
        internal
        view
        returns (
            uint160 price,
            int24 tick,
            uint16 feeZto,
            uint16 feeOtz,
            uint16 timepointIndex,
            uint8 communityFeeToken0,
            uint8 communityFeeToken1,
            bool unlocked
        )
    {
        bytes memory returndata =
            address(pool).functionStaticCall(
                abi.encodeWithSelector(pool.globalState.selector),
                "SafeAlgebraPool: low-level call failed"
            );
        return
            abi.decode(
                returndata,
                (uint160, int24, uint16, uint16, uint16, uint8, uint8, bool)
            );
    }
}

