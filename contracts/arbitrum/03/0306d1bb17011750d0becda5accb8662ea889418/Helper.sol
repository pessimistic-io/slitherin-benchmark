// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Context.sol";
import "./IMarket.sol";
import "./IBank.sol";
import "./IStakePool.sol";
import "./IHelper.sol";

contract Helper is Context, IHelper {
    using SafeERC20 for IERC20;

    // Chaos token address.
    IERC20 public override Chaos;
    // prChaos token address.
    IERC20 public override prChaos;
    // Order token address.
    IERC20 public override Order;
    // Market contract address.
    IMarket public override market;
    // Bank contract address.
    IBank public override bank;
    // Pool contract address.
    IStakePool public override pool;

    constructor(
        IERC20 _Chaos,
        IERC20 _prChaos,
        IERC20 _Order,
        IMarket _market,
        IBank _bank,
        IStakePool _pool
    ) {
        Chaos = _Chaos;
        prChaos = _prChaos;
        Order = _Order;
        market = _market;
        bank = _bank;
        pool = _pool;
    }

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
    ) public override {
        IERC20(token).safeTransferFrom(_msgSender(), address(this), tokenWorth);
        IERC20(token).approve(address(market), tokenWorth);
        (uint256 chaos, ) = market.buyFor(
            token,
            tokenWorth,
            desired,
            _msgSender()
        );
        Chaos.approve(address(pool), chaos);
        pool.depositFor(0, chaos, _msgSender());
        if (borrow) {
            borrowAndInvest((chaos * market.f()) / 1e18);
        }
    }

    /**
     * @dev Reinvest stablecoin to ONC.
     *      1. realize prChaos with stablecoin
     *      2. stake Chaos to pool
     * @param token - Stablecoin address
     * @param amount - prChaos amount
     * @param desired -  Maximum amount of stablecoin users are willing to pay(used to realize prChaos)
     */
    function reinvest(
        address token,
        uint256 amount,
        uint256 desired
    ) external override {
        prChaos.transferFrom(_msgSender(), address(this), amount);
        (, uint256 worth) = market.estimateRealize(amount, token);
        IERC20(token).safeTransferFrom(_msgSender(), address(this), worth);
        IERC20(token).approve(address(market), worth);
        prChaos.approve(address(market), amount);
        market.realizeFor(amount, token, desired, _msgSender());
        Chaos.approve(address(pool), amount);
        pool.depositFor(0, amount, _msgSender());
    }

    /**
     * @dev Borrow Order and invest to ONC.
     *      1. borrow Order
     *      2. buy Chaos with Order
     *      3. stake Chaos to pool
     * @param amount - Amount of Order
     */
    function borrowAndInvest(uint256 amount) public override {
        (uint256 borrowed, ) = bank.borrowFrom(_msgSender(), amount);
        Order.approve(address(market), borrowed);
        (uint256 chaos, ) = market.buyFor(
            address(Order),
            borrowed,
            0,
            _msgSender()
        );
        Chaos.approve(address(pool), chaos);
        pool.depositFor(0, chaos, _msgSender());
    }
}

