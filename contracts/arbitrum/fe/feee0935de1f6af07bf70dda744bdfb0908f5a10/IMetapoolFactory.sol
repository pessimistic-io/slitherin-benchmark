// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.7;

/**
 * Documentation based on https://curve.readthedocs.io/factory-deployer.html
 */
interface IMetapoolFactory {
    /**
     * Convert coin addresses into indices for use with pool methods.
     *
     * Returns the index of _from, index of _to, and a boolean indicating
     * if the coins are considered underlying in the given pool.
     *
     * @dev Example:
     *      >>> factory.get_coin_indices(pool, token1, token2)
     *      (0, 2, true)
     *
     * Based on the above call, we know:
     *  - the index of the coin we are swapping out of is 2
     *  - the index of the coin we are swapping into is 1
     *  - the coins are considred underlying, so we must call exchange_underlying
     *
     * From this information we can perform a token swap:
     *      >>> swap = Contract('0xFD9f9784ac00432794c8D370d4910D2a3782324C')
     *      >>> swap.exchange_underlying(2, 1, 1e18, 0, {'from': alice})
     */
    function get_coin_indices(
        address pool,
        address _from,
        address _to
    )
        external
        view
        returns (
            int128,
            int128,
            bool
        );
}

