// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./IMetapoolFactory.sol";
import "./IERC20.sol";
import "./IStableSwap.sol";

contract CurveUtils {
    /**
     * @notice Swaps tokens in a curve.fi metapool
     * @param from the token to be sent
     * @param to the token to be received
     * @param amount the amount of {from} to send
     * @param metapoolFactory curve.fi metapool factory (the factory that deployed {pool})
     * @param pool The metapool that has {from} and {to} as either tokens or underlying tokens
     */
    function _swapCurveTokens(
        address from,
        address to,
        uint256 amount,
        address metapoolFactory,
        address pool
    ) internal {
        (
            int128 fromIndex,
            int128 toIndex,
            bool useUnderlying
        ) = IMetapoolFactory(metapoolFactory).get_coin_indices(pool, from, to);

        IERC20(from).approve(pool, amount);

        // min out is not handled here, which is why the last param is zero
        if (useUnderlying) {
            IStableSwap(pool).exchange_underlying(
                fromIndex,
                toIndex,
                amount,
                0
            );
        } else {
            IStableSwap(pool).exchange(fromIndex, toIndex, amount, 0);
        }
    }
}

