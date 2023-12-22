// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "./ReentrancyGuardUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IPerpetual.sol";

import "./Constant.sol";
import "./OrderData.sol";

import "./TradeModule.sol";
import "./OrderModule.sol";
import "./LiquidityPoolModule.sol";

import "./Storage.sol";
import "./Type.sol";

contract PerpetualShutdown is Storage, ReentrancyGuardUpgradeable /* , IPerpetual */ {
    using OrderData for bytes;
    using OrderData for uint32;
    using OrderModule for LiquidityPoolStorage;
    using TradeModule for LiquidityPoolStorage;
    using LiquidityPoolModule for LiquidityPoolStorage;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    // shutdown // deprecated
    // shutdown function setTargetLeverage(
    // shutdown     uint256 perpetualIndex,
    // shutdown     address trader,
    // shutdown     int256 targetLeverage
    // shutdown )
    // shutdown     external
    // shutdown     onlyAuthorized(
    // shutdown         trader,
    // shutdown         Constant.PRIVILEGE_TRADE | Constant.PRIVILEGE_DEPOSIT | Constant.PRIVILEGE_WITHDRAW
    // shutdown     )
    // shutdown {
    // shutdown     require(trader != address(0), "invalid trader");
    // shutdown     require(targetLeverage % Constant.SIGNED_ONE == 0, "targetLeverage must be integer");
    // shutdown     require(targetLeverage > 0, "targetLeverage is negative");
    // shutdown     _liquidityPool.setTargetLeverage(perpetualIndex, trader, targetLeverage);
    // shutdown }

    // shutdown /**
    // shutdown  * @notice  Deposit collateral to the perpetual.
    // shutdown  *          Can only called when the perpetual's state is "NORMAL".
    // shutdown  *          This method will always increase `cash` amount in trader's margin account.
    // shutdown  *
    // shutdown  * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
    // shutdown  * @param   trader          The address of the trader.
    // shutdown  * @param   amount          The amount of collateral to deposit. The amount always use decimals 18.
    // shutdown  */
    // shutdown function deposit(
    // shutdown     uint256 perpetualIndex,
    // shutdown     address trader,
    // shutdown     int256 amount
    // shutdown )
    // shutdown     external
    // shutdown     override
    // shutdown     nonReentrant
    // shutdown     onlyNotUniverseSettled
    // shutdown     onlyAuthorized(trader, Constant.PRIVILEGE_DEPOSIT)
    // shutdown {
    // shutdown     require(
    // shutdown         _liquidityPool.perpetuals[perpetualIndex].state == PerpetualState.NORMAL,
    // shutdown         "perpetual should be in NORMAL state"
    // shutdown     );
    // shutdown     require(trader != address(0), "invalid trader");
    // shutdown     require(amount > 0, "invalid amount");
    // shutdown     _liquidityPool.deposit(perpetualIndex, trader, amount);
    // shutdown }

    // shutdown /**
    // shutdown  * @notice  Withdraw collateral from the trader's account of the perpetual.
    // shutdown  *          After withdrawn, trader shall at least has maintenance margin left in account.
    // shutdown  *          Can only called when the perpetual's state is "NORMAL".
    // shutdown  *          Margin account must at least keep
    // shutdown  *          The trader's cash will decrease in the perpetual.
    // shutdown  *          Need to update the funding state and the oracle price of each perpetual before
    // shutdown  *          and update the funding rate of each perpetual after
    // shutdown  *
    // shutdown  * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
    // shutdown  * @param   trader          The address of the trader.
    // shutdown  * @param   amount          The amount of collateral to withdraw. The amount always use decimals 18.
    // shutdown  */
    // shutdown function withdraw(
    // shutdown     uint256 perpetualIndex,
    // shutdown     address trader,
    // shutdown     int256 amount
    // shutdown )
    // shutdown     external
    // shutdown     override
    // shutdown     nonReentrant
    // shutdown     onlyNotUniverseSettled
    // shutdown     syncState(false)
    // shutdown     onlyAuthorized(trader, Constant.PRIVILEGE_WITHDRAW)
    // shutdown {
    // shutdown     require(
    // shutdown         _liquidityPool.perpetuals[perpetualIndex].state == PerpetualState.NORMAL,
    // shutdown         "perpetual should be in NORMAL state"
    // shutdown     );
    // shutdown     require(trader != address(0), "invalid trader");
    // shutdown     require(amount > 0, "invalid amount");
    // shutdown     _liquidityPool.withdraw(perpetualIndex, trader, amount);
    // shutdown }

    /**
     * @notice  If the state of the perpetual is "CLEARED", anyone can settle
     *          trader's account in the perpetual. Which means to calculate how much the collateral should be returned
     *          to the trader, return it to trader's wallet and clear the trader's cash and position in the perpetual.
     *
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool
     * @param   trader          The address of the trader.
     */
    function settle(uint256 perpetualIndex, address trader)
        external
        // shutdown onlyAuthorized(trader, Constant.PRIVILEGE_WITHDRAW)
        nonReentrant
    {
        require(trader != address(0), "invalid trader");
        require(
            _liquidityPool.perpetuals[perpetualIndex].state == PerpetualState.CLEARED,
            "perpetual should be in CLEARED state"
        );
        _liquidityPool.settle(perpetualIndex, trader);
    }

    /**
     * @notice  Clear the next active account of the perpetual which state is "EMERGENCY" and send gas reward of collateral
     *          to sender. If all active accounts are cleared, the clear progress is done and the perpetual's state will
     *          change to "CLEARED". Active means the trader's account is not empty in the perpetual.
     *          Empty means cash and position are zero
     *
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
     */
    function clear(uint256 perpetualIndex) external nonReentrant {
        require(
            _liquidityPool.perpetuals[perpetualIndex].state == PerpetualState.EMERGENCY,
            "perpetual should be in EMERGENCY state"
        );
        _liquidityPool.clear(perpetualIndex, _msgSender());
    }

    // shutdown /**
    // shutdown  * @notice  Trade with AMM in the perpetual, require sender is granted the trade privilege by the trader.
    // shutdown  *          The trading price is determined by the AMM based on the index price of the perpetual.
    // shutdown  *          A successful trade should:
    // shutdown  *            - The trade transaction not exceeds deadline;
    // shutdown  *            - Current liquidity of amm is enough to make the deal;
    // shutdown  *            - to open position:
    // shutdown  *              - Trader's margin balance must be greater then or equal to initial margin after trading;
    // shutdown  *              - Full trading fee will be charged if trader is opening position.
    // shutdown  *            - to close position:
    // shutdown  *              - Trader's margin balance must be greater then or equal to 0 after trading;
    // shutdown  *              - Trader need to pay the trading fee as much as possible before all the margin balance drained.
    // shutdown  *          If one trade transaction does close and open at same time (Open positions in the opposite direction)
    // shutdown  *          It will be treat as opening position.
    // shutdown  *
    // shutdown  *
    // shutdown  *          Flags is a 32 bit uint value which indicates: (from highest bit)
    // shutdown  *            31               27 26                     7 6              0
    // shutdown  *           +---+---+---+---+---+------------------------+----------------+
    // shutdown  *           | C | M | S | T | R | Target leverage 20bits | Reserved 7bits |
    // shutdown  *           +---+---+---+---+---+------------------------+----------------+
    // shutdown  *             |   |   |   |   |   ` Target leverage  Fixed-point decimal with 2 decimal digits. 
    // shutdown  *             |   |   |   |   |                      0 means don't automatically deposit / withdraw.
    // shutdown  *             |   |   |   |   `---  Reserved
    // shutdown  *             |   |   |   `-------  Take profit      Only available in brokerTrade mode.
    // shutdown  *             |   |   `-----------  Stop loss        Only available in brokerTrade mode.
    // shutdown  *             |   `---------------  Market order     Do not check limit price during trading.
    // shutdown  *             `-------------------  Close only       Only close position during trading.
    // shutdown  *          For stop loss and take profit, see `validateTriggerPrice` in OrderModule.sol for details.
    // shutdown  *
    // shutdown  * @param   perpetualIndex  The index of the perpetual in liquidity pool.
    // shutdown  * @param   trader          The address of trader.
    // shutdown  * @param   amount          The amount of position to trader, positive for buying and negative for selling. The amount always use decimals 18.
    // shutdown  * @param   limitPrice      The worst price the trader accepts.
    // shutdown  * @param   deadline        The deadline of trade transaction.
    // shutdown  * @param   referrer        The address of referrer who will get rebate from the deal.
    // shutdown  * @param   flags           The flags of the trade.
    // shutdown  * @return  tradeAmount     The amount of positions actually traded in the transaction. The amount always use decimals 18.
    // shutdown  */
    // shutdown function trade(
    // shutdown     uint256 perpetualIndex,
    // shutdown     address trader,
    // shutdown     int256 amount,
    // shutdown     int256 limitPrice,
    // shutdown     uint256 deadline,
    // shutdown     address referrer,
    // shutdown     uint32 flags
    // shutdown )
    // shutdown     external
    // shutdown     override
    // shutdown     onlyAuthorized(
    // shutdown         trader,
    // shutdown         flags.useTargetLeverage()
    // shutdown             ? Constant.PRIVILEGE_TRADE |
    // shutdown                 Constant.PRIVILEGE_DEPOSIT |
    // shutdown                 Constant.PRIVILEGE_WITHDRAW
    // shutdown             : Constant.PRIVILEGE_TRADE
    // shutdown     )
    // shutdown     syncState(false)
    // shutdown     returns (int256 tradeAmount)
    // shutdown {
    // shutdown     require(trader != address(0), "invalid trader");
    // shutdown     require(amount != 0, "invalid amount");
    // shutdown     require(deadline >= block.timestamp, "deadline exceeded");
    // shutdown     tradeAmount = _trade(perpetualIndex, trader, amount, limitPrice, referrer, flags);
    // shutdown }

    // shutdown /**
    // shutdown  * @notice  Trade with AMM by the order, initiated by the broker. order is passed in through packed data structure.
    // shutdown  *          All the fields of order are verified by signature.
    // shutdown  *          See `trade` for details.
    // shutdown  * @param   orderData   The order data object
    // shutdown  * @param   amount      The amount of position to trader, positive for buying and negative for selling.
    // shutdown  *                      This amount should be lower then or equal to amount in `orderData`. The amount always use decimals 18.
    // shutdown  * @return  tradeAmount The amount of positions actually traded in the transaction. The amount always use decimals 18.
    // shutdown  */
    // shutdown function brokerTrade(bytes memory orderData, int256 amount)
    // shutdown     external
    // shutdown     override
    // shutdown     syncState(false)
    // shutdown     returns (int256 tradeAmount)
    // shutdown {
    // shutdown     Order memory order = orderData.decodeOrderData();
    // shutdown     bytes memory signature = orderData.decodeSignature();
    // shutdown     _liquidityPool.validateSignature(order, signature);
    // shutdown     _liquidityPool.validateOrder(order, amount);
    // shutdown     _liquidityPool.validateTriggerPrice(order);
    // shutdown     tradeAmount = _trade(
    // shutdown         order.perpetualIndex,
    // shutdown         order.trader,
    // shutdown         amount,
    // shutdown         order.limitPrice,
    // shutdown         order.referrer,
    // shutdown         order.flags
    // shutdown     );
    // shutdown }

    // shutdown /**
    // shutdown  * @notice  Liquidate the trader if the trader's margin balance is lower than maintenance margin (unsafe).
    // shutdown  *          Liquidate can be considered as a forced trading between AMM and unsafe margin account;
    // shutdown  *          Based on current liquidity of AMM, it may take positions up to an amount equal to all the position
    // shutdown  *          of the unsafe account. Besides the position, trader need to pay an extra penalty to AMM
    // shutdown  *          for taking the unsafe assets. See TradeModule.sol for ehe strategy of penalty.
    // shutdown  *
    // shutdown  *          The liquidate price will be determined by AMM.
    // shutdown  *          Caller of this method can be anyone, then get a reward to make up for transaction gas fee.
    // shutdown  *
    // shutdown  *          If a trader's margin balance is lower than 0 (bankrupt), insurance fund will be use to fill the loss
    // shutdown  *          to make the total profit and loss balanced. (first the `insuranceFund` then the `donatedInsuranceFund`)
    // shutdown  *
    // shutdown  *          If insurance funds are drained, the state of perpetual will turn to enter "EMERGENCY" than shutdown.
    // shutdown  *          Can only liquidate when the perpetual's state is "NORMAL".
    // shutdown  *
    // shutdown  * @param   perpetualIndex      The index of the perpetual in liquidity pool
    // shutdown  * @param   trader              The address of trader to be liquidated.
    // shutdown  * @return  liquidationAmount   The amount of positions actually liquidated in the transaction. The amount always use decimals 18.
    // shutdown  */
    // shutdown function liquidateByAMM(uint256 perpetualIndex, address trader)
    // shutdown     external
    // shutdown     override
    // shutdown     nonReentrant
    // shutdown     onlyNotUniverseSettled
    // shutdown     syncState(false)
    // shutdown     returns (int256 liquidationAmount)
    // shutdown {
    // shutdown     require(_isAMMKeeper(perpetualIndex, _msgSender()), "caller must be keeper");
    // shutdown     require(
    // shutdown         _liquidityPool.perpetuals[perpetualIndex].state == PerpetualState.NORMAL,
    // shutdown         "perpetual should be in NORMAL state"
    // shutdown     );
    // shutdown     require(trader != address(0), "invalid trader");
    // shutdown     require(trader != address(this), "cannot liquidate AMM");
    // shutdown     liquidationAmount = _liquidityPool.liquidateByAMM(perpetualIndex, _msgSender(), trader);
    // shutdown }

    // shutdown /**
    // shutdown  * @notice  This method is generally consistent with `liquidateByAMM` function, but there some difference:
    // shutdown  *           - The liquidation price is no longer determined by AMM, but the mark price;
    // shutdown  *           - The penalty is taken by trader who takes position but AMM;
    // shutdown  *
    // shutdown  * @param   perpetualIndex      The index of the perpetual in liquidity pool.
    // shutdown  * @param   liquidator          The address of liquidator to receive the liquidated position.
    // shutdown  * @param   trader              The address of trader to be liquidated.
    // shutdown  * @param   amount              The amount of position to be taken from liquidated trader. The amount always use decimals 18.
    // shutdown  * @param   limitPrice          The worst price liquidator accepts.
    // shutdown  * @param   deadline            The deadline of transaction.
    // shutdown  * @return  liquidationAmount   The amount of positions actually liquidated in the transaction.
    // shutdown  */
    // shutdown function liquidateByTrader(
    // shutdown     uint256 perpetualIndex,
    // shutdown     address liquidator,
    // shutdown     address trader,
    // shutdown     int256 amount,
    // shutdown     int256 limitPrice,
    // shutdown     uint256 deadline
    // shutdown )
    // shutdown     external
    // shutdown     override
    // shutdown     nonReentrant
    // shutdown     onlyNotUniverseSettled
    // shutdown     onlyAuthorized(liquidator, Constant.PRIVILEGE_LIQUIDATE)
    // shutdown     syncState(false)
    // shutdown     returns (int256 liquidationAmount)
    // shutdown {
    // shutdown     require(
    // shutdown         _liquidityPool.perpetuals[perpetualIndex].state == PerpetualState.NORMAL,
    // shutdown         "perpetual should be in NORMAL state"
    // shutdown     );
    // shutdown     require(trader != address(0), "invalid trader");
    // shutdown     require(trader != address(this), "cannot liquidate AMM");
    // shutdown     require(amount != 0, "invalid amount");
    // shutdown     require(limitPrice >= 0, "invalid limit price");
    // shutdown     require(deadline >= block.timestamp, "deadline exceeded");
    // shutdown     liquidationAmount = _liquidityPool.liquidateByTrader(
    // shutdown         perpetualIndex,
    // shutdown         liquidator,
    // shutdown         trader,
    // shutdown         amount,
    // shutdown         limitPrice
    // shutdown     );
    // shutdown }

    // shutdown function _trade(
    // shutdown     uint256 perpetualIndex,
    // shutdown     address trader,
    // shutdown     int256 amount,
    // shutdown     int256 limitPrice,
    // shutdown     address referrer,
    // shutdown     uint32 flags
    // shutdown ) internal onlyNotUniverseSettled returns (int256 tradeAmount) {
    // shutdown     require(
    // shutdown         _liquidityPool.perpetuals[perpetualIndex].state == PerpetualState.NORMAL,
    // shutdown         "perpetual should be in NORMAL state"
    // shutdown     );
    // shutdown     tradeAmount = _liquidityPool.trade(
    // shutdown         perpetualIndex,
    // shutdown         trader,
    // shutdown         amount,
    // shutdown         limitPrice,
    // shutdown         referrer,
    // shutdown         flags
    // shutdown     );
    // shutdown }

    // shutdown function _isAMMKeeper(uint256 perpetualIndex, address liquidator) internal view returns (bool) {
    // shutdown     EnumerableSetUpgradeable.AddressSet storage whitelist = _liquidityPool
    // shutdown         .perpetuals[perpetualIndex]
    // shutdown         .ammKeepers;
    // shutdown     if (whitelist.length() == 0) {
    // shutdown         return IPoolCreatorFull(_liquidityPool.creator).isKeeper(liquidator);
    // shutdown     } else {
    // shutdown         return whitelist.contains(liquidator);
    // shutdown     }
    // shutdown }

    bytes32[50] private __gap;
}

