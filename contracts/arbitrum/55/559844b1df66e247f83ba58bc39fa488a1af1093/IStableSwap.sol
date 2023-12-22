// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.7;

/**
 * Documentation based on https://curve.readthedocs.io/factory-pools.html
 */
interface IStableSwap {
    /**
     * Perform an exchange between two underlying coins.
     * Index values can be found using get_underlying_coins within the factory contract.
     *
     * @param i Index value of the underlying token to send.
     * @param j Index value of the underlying token to receive.
     * @param _dx: The amount of i being exchanged.
     * @param _min_dy: The minimum amount of j to receive. If the swap would result in
     * less, the  * transaction will revert.
     *
     * @return the amount of j received in the exchange.
     */
    function exchange(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy
    ) external returns (uint256);

    /**
     * Performs an exchange between two tokens.
     * Index values can be found using the coins public getter method,
     * or get_coins within the factory contract.
     *
     * @param i Index value of the token to send.
     * @param j Index value of the token to receive.
     * @param _dx: The amount of i being exchanged.
     * @param _min_dy: The minimum amount of j to receive. If the swap would result in
     * less, the  * transaction will revert.
     *
     * @return the amount of j received in the exchange.
     */
    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy
    ) external returns (uint256);
}

