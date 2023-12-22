// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IMarket.sol";
import "./IBank.sol";
import "./IStakePool.sol";

interface IHelper {
    // Chaos token address.
    function Chaos() external view returns (IERC20);

    // prChaos token address.
    function prChaos() external view returns (IERC20);

    // Order token address.
    function Order() external view returns (IERC20);

    // Order token address.
    function market() external view returns (IMarket);

    // Market contract address.
    function bank() external view returns (IBank);

    // Bank contract address.
    function pool() external view returns (IStakePool);

    /**
     * @dev Invest stablecoin to ONC.
     *      1. buy Chaos with stablecoin
     *      2. stake Chaos to pool
     *      3. borrow Order(if needed)
     *      4. buy Chaos with Order(if needed)
     *      5. stake Chaos to pool(if needed)
     * @param token - Stablecoin address
     * @param tokenWorth - Amount of stablecoin
     * @param desired - Minimum amount of Chaos user want to buy
     * @param borrow - Whether to borrow Order
     */
    function invest(
        address token,
        uint256 tokenWorth,
        uint256 desired,
        bool borrow
    ) external;

    /**
     * @dev Reinvest stablecoin to ONC.
     *      1. claim reward
     *      2. realize prChaos with stablecoin
     *      3. stake Chaos to pool
     * @param token - Stablecoin address
     * @param amount - prChaos amount
     * @param desired -  Maximum amount of stablecoin users are willing to pay(used to realize prChaos)
     */
    function reinvest(
        address token,
        uint256 amount,
        uint256 desired
    ) external;

    /**
     * @dev Borrow Order and invest to ONC.
     *      1. borrow Order
     *      2. buy Chaos with Order
     *      3. stake Chaos to pool
     * @param amount - Amount of Order
     */
    function borrowAndInvest(uint256 amount) external;
}

