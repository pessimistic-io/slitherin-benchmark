// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableInternal.sol";
import "./IERC1155.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./IWETH.sol";
import "./SafeCast.sol";
import "./SafeERC20.sol";

import "./OptionMath.sol";

import "./IPremiaPool.sol";

import "./IVault.sol";

import "./AuctionStorage.sol";
import "./IAuctionEvents.sol";

/**
 * @title Knox Dutch Auction Internal Contract
 */

contract AuctionInternal is IAuctionEvents, OwnableInternal {
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64Token for int128;
    using ABDKMath64x64Token for uint256;
    using AuctionStorage for AuctionStorage.Layout;
    using EnumerableSet for EnumerableSet.UintSet;
    using OptionMath for uint256;
    using OrderBook for OrderBook.Index;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    bool internal immutable isCall;
    uint8 internal immutable baseDecimals;
    uint8 internal immutable underlyingDecimals;

    IERC20 public immutable ERC20;
    IPremiaPool public immutable Pool;
    IVault public immutable Vault;
    IWETH public immutable WETH;

    constructor(
        bool _isCall,
        address pool,
        address vault,
        address weth
    ) {
        isCall = _isCall;

        Pool = IPremiaPool(pool);
        IPremiaPool.PoolSettings memory settings = Pool.getPoolSettings();
        address asset = isCall ? settings.underlying : settings.base;

        baseDecimals = IERC20Metadata(settings.base).decimals();
        underlyingDecimals = IERC20Metadata(settings.underlying).decimals();

        ERC20 = IERC20(asset);
        Vault = IVault(vault);
        WETH = IWETH(weth);
    }

    /************************************************
     *  ACCESS CONTROL
     ***********************************************/

    /**
     * @dev Throws if called by any account other than the vault
     */
    modifier onlyVault() {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        require(msg.sender == address(Vault), "!vault");
        _;
    }

    /**
     * @dev Throws if limit orders are not allowed
     * @param auction storage params
     */
    function _limitOrdersAllowed(AuctionStorage.Auction storage auction)
        internal
        view
    {
        require(
            AuctionStorage.Status.INITIALIZED == auction.status,
            "status != initialized"
        );
        _auctionHasNotEnded(auction);
    }

    /**
     * @dev Throws if market orders are not allowed
     * @param auction storage params
     */
    function _marketOrdersAllowed(AuctionStorage.Auction storage auction)
        internal
        view
    {
        require(
            AuctionStorage.Status.INITIALIZED == auction.status,
            "status != initialized"
        );
        _auctionHasStarted(auction);
        _auctionHasNotEnded(auction);
    }

    /**
     * @dev Throws if auction has not started.
     * @param auction storage params
     */
    function _auctionHasStarted(AuctionStorage.Auction storage auction)
        private
        view
    {
        require(auction.startTime > 0, "start time is not set");
        require(block.timestamp >= auction.startTime, "auction not started");
    }

    /**
     * @dev Throws if auction has ended.
     * @param auction storage params
     */
    function _auctionHasNotEnded(AuctionStorage.Auction storage auction)
        private
        view
    {
        require(auction.endTime > 0, "end time is not set");
        require(block.timestamp <= auction.endTime, "auction has ended");
    }

    /************************************************
     *  PRICING
     ***********************************************/

    /**
     * @notice returns the last price paid during the auction
     * @param auction storage params
     * @return price as 64x64 fixed point number
     */
    function _lastPrice64x64(AuctionStorage.Auction storage auction)
        internal
        view
        returns (int128)
    {
        return auction.lastPrice64x64;
    }

    /**
     * @notice calculates the current price using the price curve function
     * @param auction storage params
     * @return price as 64x64 fixed point number
     */
    function _priceCurve64x64(AuctionStorage.Auction storage auction)
        internal
        view
        returns (int128)
    {
        uint256 startTime = auction.startTime;
        uint256 totalTime = auction.endTime - auction.startTime;

        int128 maxPrice64x64 = auction.maxPrice64x64;
        int128 minPrice64x64 = auction.minPrice64x64;

        /**
         *
         * price curve equation:
         * assumes max price is always greater than min price
         * assumes the time remaining is in the range of 0 and 1
         * ------------------------------
         * time_remaning_percent(t) = (t - time_start) / time_total
         * price(t) = max_price - time_remaning_percent(t) * (max_price - min_price)
         *
         */

        if (block.timestamp <= startTime) return maxPrice64x64;
        if (block.timestamp >= auction.endTime) return minPrice64x64;

        uint256 elapsed = block.timestamp - startTime;
        int128 timeRemaining64x64 = elapsed.divu(totalTime);

        int128 x = maxPrice64x64.sub(minPrice64x64);
        int128 y = timeRemaining64x64.mul(x);
        return maxPrice64x64.sub(y);
    }

    /**
     * @notice returns the current price established by the price curve if the auction
     * is still ongoing, otherwise the last price paid is returned
     * @param auction storage params
     * @return price as 64x64 fixed point number
     */
    function _clearingPrice64x64(AuctionStorage.Auction storage auction)
        internal
        view
        returns (int128)
    {
        if (
            auction.status == AuctionStorage.Status.FINALIZED ||
            auction.status == AuctionStorage.Status.PROCESSED ||
            auction.status == AuctionStorage.Status.CANCELLED
        ) {
            return _lastPrice64x64(auction);
        }
        return _priceCurve64x64(auction);
    }

    /**
     * @notice calculates and sets the option max and min price
     * @param l auction storage layout
     * @param auction storage params
     * @param epoch epoch id
     * @param spot64x64 spot price of the underlying as 64x64 fixed point number
     * @param timeToMaturity64x64 time remaining until maturity as a 64x64 fixed point number
     */
    function _setAuctionPrices(
        AuctionStorage.Layout storage l,
        AuctionStorage.Auction storage auction,
        uint64 epoch,
        int128 spot64x64,
        int128 timeToMaturity64x64
    ) internal {
        int128 strike64x64 = auction.strike64x64;

        // calculates the further OTM strike price
        int128 offsetAmount64x64 = strike64x64.mul(l.deltaOffset64x64);
        int128 offsetStrike64x64 =
            isCall
                ? strike64x64.add(offsetAmount64x64)
                : strike64x64.sub(offsetAmount64x64);

        /**
         * it is assumed that the rounded strike price will always be further ITM than the offset
         * strike price. the further ITM option will always be more expensive and will therefore
         * be used to determine the max price of the auction. likewise, the offset strike price
         * (further OTM) should resemble a cheaper option and it is therefore used as the min
         * option price in our auction.
         *
         *
         * Call Option
         * -----------
         * Strike    Rounded Strike             Offset Strike
         *   |  ---------> |                          |
         *   |             |                          |
         * -----------------------Price------------------------>
         *
         *
         * Put Option
         * -----------
         * Offset Strike              Rounded Strike    Strike
         *       |                           | <--------- |
         *       |                           |            |
         * -----------------------Price------------------------>
         *
         *
         */

        // calculates the auction max price using the strike price (further ITM)
        auction.maxPrice64x64 = l.Pricer.getBlackScholesPrice64x64(
            spot64x64,
            strike64x64,
            timeToMaturity64x64,
            isCall
        );

        // calculates the auction min price using the offset strike price (further OTM)
        auction.minPrice64x64 = l.Pricer.getBlackScholesPrice64x64(
            spot64x64,
            offsetStrike64x64,
            timeToMaturity64x64,
            isCall
        );

        if (isCall) {
            // denominates price in the collateral asset
            auction.maxPrice64x64 = auction.maxPrice64x64.div(spot64x64);
            auction.minPrice64x64 = auction.minPrice64x64.div(spot64x64);
        }

        emit AuctionPricesSet(
            epoch,
            strike64x64,
            offsetStrike64x64,
            spot64x64,
            auction.maxPrice64x64,
            auction.minPrice64x64
        );
    }

    /**
     * @notice validates the max and min prices
     * @param auction storage params
     * @param epoch epoch id
     */
    function _validateAuctionPrices(
        AuctionStorage.Auction storage auction,
        uint64 epoch
    ) internal {
        if (
            auction.maxPrice64x64 <= 0 ||
            auction.minPrice64x64 <= 0 ||
            auction.maxPrice64x64 <= auction.minPrice64x64
        ) {
            // if either price is 0 or the max price is less than or equal to the min price,
            // the auction should always be cancelled.
            _cancel(auction, epoch);
        }
    }

    /************************************************
     *  WITHDRAW
     ***********************************************/

    /**
     * @notice withdraws any amount(s) owed to the buyer (fill and/or refund)
     * @param l auction storage layout
     * @param epoch epoch id
     */
    function _withdraw(AuctionStorage.Layout storage l, uint64 epoch) internal {
        (uint256 refund, uint256 fill) =
            _previewWithdraw(l, false, epoch, msg.sender);

        // removes all unique order ids associated with epoch
        _removeUniqueOrderId(l, epoch, 0);

        // fetches the exercised value of the options
        (bool expired, uint256 exercisedAmount) =
            _getExerciseAmount(l, epoch, fill);

        if (expired) {
            if (exercisedAmount > 0) {
                // if expired ITM, adjust refund by the amount exercised
                refund += exercisedAmount;
            }

            // set fill to 0, buyer will not receive any long tokens
            fill = 0;
        }

        if (fill > 0) {
            // transfers long tokens to msg.sender
            Pool.safeTransferFrom(
                address(this),
                msg.sender,
                l.auctions[epoch].longTokenId,
                fill,
                ""
            );
        }

        if (refund > 0) {
            // transfers refunded premium to msg.sender
            ERC20.safeTransfer(msg.sender, refund);
        }

        emit OrderWithdrawn(epoch, msg.sender, refund, fill);
    }

    /**
     * @notice calculates amount(s) owed to the buyer
     * @param epoch epoch id
     * @param buyer address of buyer
     * @return amount refunded
     * @return amount filled
     */
    function _previewWithdraw(uint64 epoch, address buyer)
        internal
        returns (uint256, uint256)
    {
        AuctionStorage.Layout storage l = AuctionStorage.layout();
        return _previewWithdraw(l, true, epoch, buyer);
    }

    /**
     * @notice traverses the orderbook and returns the refund and fill amounts
     * @param l auction storage layout
     * @param epoch epoch id
     * @param buyer address of buyer
     * @return amount refunded
     * @return amount filled
     */
    function _previewWithdraw(
        AuctionStorage.Layout storage l,
        bool isPreview,
        uint64 epoch,
        address buyer
    ) private returns (uint256, uint256) {
        AuctionStorage.Auction storage auction = l.auctions[epoch];
        OrderBook.Index storage orderbook = l.orderbooks[epoch];

        uint256 refund;
        uint256 fill;

        int128 lastPrice64x64 = _clearingPrice64x64(auction);
        uint256 totalUnclaimedContracts = auction.totalUnclaimedContracts;

        // traverse the order book and return orders placed by the buyer until the end of the orderbook has been reached
        OrderBook.Data memory data = orderbook._getOrderById(orderbook._head());
        do {
            uint256 next = orderbook._getNextOrder(data.id);

            if (data.buyer == buyer) {
                uint256 claimed;
                uint256 paid = data.price64x64.mulu(data.size);

                if (
                    auction.status != AuctionStorage.Status.CANCELLED &&
                    totalUnclaimedContracts > 0 &&
                    data.price64x64 >= lastPrice64x64
                ) {
                    // if the auction has not been cancelled, and the order price is greater than or
                    // equal to the last price, fill the order and calculate the refund amount
                    uint256 cost = lastPrice64x64.mulu(data.size);

                    if (data.size > totalUnclaimedContracts) {
                        // if part of the current order exceeds the total contracts available, partially
                        // fill the order, and refund the remainder
                        cost = lastPrice64x64.mulu(totalUnclaimedContracts);
                        fill += totalUnclaimedContracts;
                        claimed += totalUnclaimedContracts;
                    } else {
                        // otherwise, fill the entire order
                        fill += data.size;
                        claimed += data.size;
                    }
                    // the refund takes the difference between the amount paid and the "true" cost of
                    // of the order. the "true" cost can be calculated when the clearing price has been
                    // set.
                    refund += paid - cost;
                } else {
                    // if no contracts are available, the auction has been cancelled, or the bid is too
                    // low, only send refund
                    refund += paid;
                }

                if (!isPreview) {
                    // if the buyer has a filled order, remove it from the unclaimed
                    // contract balance
                    auction.totalUnclaimedContracts -= claimed;

                    // when a withdrawal is made, remove the order from the order book
                    orderbook._remove(data.id);
                }

                // claimed amount is reset after every filled order
                claimed = 0;
            }

            if (totalUnclaimedContracts > 0) {
                if (data.size > totalUnclaimedContracts) {
                    totalUnclaimedContracts = 0;
                } else {
                    totalUnclaimedContracts -= data.size;
                }
            }

            data = orderbook._getOrderById(next);
        } while (data.id != 0);

        return (refund, fill);
    }

    /************************************************
     *  FINALIZE AUCTION
     ***********************************************/

    /**
     * @notice traverses the orderbook and checks if the auction has reached 100% utilization
     * @param l auction storage layout
     * @param epoch epoch id
     * @return true if the auction has reached 100% utilization
     */
    function _processOrders(AuctionStorage.Layout storage l, uint64 epoch)
        private
        returns (bool)
    {
        OrderBook.Index storage orderbook = l.orderbooks[epoch];
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        // if the total contracts has not been set for the auction, the vault contract will be
        // queried and the amount will be determined from the collateral in the vault.
        if (auction.totalContracts <= 0) {
            uint256 totalContracts = _getTotalContracts(auction);

            // auction is cancelled if there are no contracts available
            if (totalContracts <= 0) {
                _cancel(auction, epoch);
                return false;
            }

            auction.totalContracts = totalContracts;
        }

        uint256 totalContractsSold;
        int128 lastPrice64x64;

        // traverse the order book and sum the contracts sold until the utilization == 100% or
        // the end of the orderbook has been reached
        OrderBook.Data memory data = orderbook._getOrderById(orderbook._head());
        do {
            uint256 next = orderbook._getNextOrder(data.id);

            // orders in the order book are sorted by price in a descending order. if the
            // order price < clearing price the last order which should be accepeted has
            // been reached.
            if (data.price64x64 < _clearingPrice64x64(auction)) break;

            // checks if utilization >= 100%
            if (totalContractsSold + data.size >= auction.totalContracts) {
                auction.lastPrice64x64 = data.price64x64;
                auction.totalContractsSold = auction.totalContracts;
                return true;
            }

            totalContractsSold += data.size;
            lastPrice64x64 = data.price64x64;

            data = orderbook._getOrderById(next);
        } while (data.id != 0);

        /**
         * sets the last price reached in the order book equal to the last price paid in the auction.
         *
         *
         * Orderbook | price curve == 96
         * ---------
         * id -  price
         * 0  -  100
         * 1  -  97 --- last price
         * 2  -  95
         * */

        auction.lastPrice64x64 = lastPrice64x64;
        auction.totalContractsSold = totalContractsSold;
        return false;
    }

    /**
     * @notice determines whether the auction has reached finality. the end criteria for the auction are
     * met if the auction has reached 100% utilization or the end time has been exceeded.
     * @param l auction storage layout
     * @param auction storage params
     * @param epoch epoch id
     */
    function _finalizeAuction(
        AuctionStorage.Layout storage l,
        AuctionStorage.Auction storage auction,
        uint64 epoch
    ) internal {
        _validateAuctionPrices(auction, epoch);

        if (
            auction.status != AuctionStorage.Status.CANCELLED &&
            (_processOrders(l, epoch) || block.timestamp > auction.endTime)
        ) {
            if (auction.totalContractsSold > 0) {
                auction.totalUnclaimedContracts = auction.totalContractsSold;
                _updateStatus(auction, AuctionStorage.Status.FINALIZED, epoch);
            } else {
                _cancel(auction, epoch);
            }
        }
    }

    /************************************************
     *  VIEW
     ***********************************************/

    /**
     * @notice calculates the total number of contracts that can be sold during the auction
     * @param auction storage params
     * @return total contracts available
     */
    function _getTotalContracts(AuctionStorage.Auction storage auction)
        private
        view
        returns (uint256)
    {
        uint256 collateral = Vault.totalCollateral();
        uint256 reserves = Vault.previewReserves();

        return
            collateral > reserves
                ? (collateral - reserves).fromCollateralToContracts(
                    isCall,
                    baseDecimals,
                    auction.strike64x64
                )
                : 0;
    }

    /************************************************
     *  PURCHASE HELPERS
     ***********************************************/

    /**
     * @notice checks whether the limit order parameters are valid and returns the cost
     * @param l auction storage layout
     * @param price64x64 max price as 64x64 fixed point number
     * @param size amount of contracts
     * @return cost of the order given the size and price
     */
    function _validateLimitOrder(
        AuctionStorage.Layout storage l,
        int128 price64x64,
        uint256 size
    ) internal view returns (uint256) {
        require(price64x64 > 0, "price <= 0");
        require(size >= l.minSize, "size < minimum");

        uint256 cost = price64x64.mulu(size);
        return cost;
    }

    /**
     * @notice checks whether the market order parameters are valid and returns the price and cost
     * @param l auction storage layout
     * @param auction storage params
     * @param size amount of contracts
     * @param maxCost max cost of buyer is willing to pay
     * @return price established by the price curve
     * @return cost of the order given the size and price
     */
    function _validateMarketOrder(
        AuctionStorage.Layout storage l,
        AuctionStorage.Auction storage auction,
        uint256 size,
        uint256 maxCost
    ) internal view returns (int128, uint256) {
        require(size >= l.minSize, "size < minimum");

        int128 price64x64 = _priceCurve64x64(auction);
        uint256 cost = price64x64.mulu(size);

        require(maxCost >= cost, "cost > maxCost");
        return (price64x64, cost);
    }

    /**
     * @notice transfers the premium to the buyer if a refund is due, ortherwise, pull funds
     * from buyer if funds are owed to the auction contract.
     * @param credited amount already paid by the buyer
     * @param cost total amount which must be paid by the buyer
     * @param buyer account being debited or credited
     */
    function _transferAssets(
        uint256 credited,
        uint256 cost,
        address buyer
    ) internal {
        if (credited > cost) {
            // refund buyer the amount overpaid
            ERC20.safeTransfer(buyer, credited - cost);
        } else if (cost > credited) {
            // an approve() by the msg.sender is required beforehand
            ERC20.safeTransferFrom(buyer, address(this), cost - credited);
        }
    }

    /**
     * @notice checks whether the market order parameters are valid and returns the price and cost
     * @param l auction storage layout
     * @param auction storage params
     * @param epoch epoch id
     * @param price64x64 max price as 64x64 fixed point number
     * @param size amount of contracts
     * @param isLimitOrder true, if the order is a limit order
     */
    function _addOrder(
        AuctionStorage.Layout storage l,
        AuctionStorage.Auction storage auction,
        uint64 epoch,
        int128 price64x64,
        uint256 size,
        bool isLimitOrder
    ) internal {
        uint128 orderId =
            l.orderbooks[epoch]
                ._insert(price64x64, size, msg.sender)
                .toUint128();

        // format the unique order id and add it to storage
        uint256 uoid = AuctionStorage._formatUniqueOrderId(epoch, orderId);
        l.uoids[msg.sender].add(uoid);

        if (block.timestamp >= auction.startTime) {
            _finalizeAuction(l, auction, epoch);
        }

        emit OrderAdded(
            epoch,
            orderId,
            msg.sender,
            price64x64,
            size,
            isLimitOrder
        );
    }

    /**
     * @notice wraps ETH sent to the contract and credits the amount, if the collateral asset
     * is not WETH, the transaction will revert
     * @param amount total collateral deposited
     * @return credited amount
     */
    function _wrapNativeToken(uint256 amount) internal returns (uint256) {
        uint256 credit;

        if (msg.value > 0) {
            require(address(ERC20) == address(WETH), "collateral != wETH");

            if (msg.value > amount) {
                // if the ETH amount is greater than the amount needed, it will be sent
                // back to the msg.sender
                unchecked {
                    (bool success, ) =
                        payable(msg.sender).call{value: msg.value - amount}("");

                    require(success, "ETH refund failed");

                    credit = amount;
                }
            } else {
                credit = msg.value;
            }

            WETH.deposit{value: credit}();
        }

        return credit;
    }

    /**
     * @notice pull token from user, send to exchangeHelper trigger a trade from
     * ExchangeHelper, and credits the amount
     * @param Exchange ExchangeHelper contract interface
     * @param s swap arguments
     * @param tokenOut token to swap for. should always equal to the collateral asset
     * @return credited amount
     */
    function _swapForPoolTokens(
        IExchangeHelper Exchange,
        IExchangeHelper.SwapArgs calldata s,
        address tokenOut
    ) internal returns (uint256) {
        if (msg.value > 0) {
            require(s.tokenIn == address(WETH), "tokenIn != wETH");
            WETH.deposit{value: msg.value}();
            WETH.safeTransfer(address(Exchange), msg.value);
        }

        if (s.amountInMax > 0) {
            IERC20(s.tokenIn).safeTransferFrom(
                msg.sender,
                address(Exchange),
                s.amountInMax
            );
        }

        uint256 amountCredited =
            Exchange.swapWithToken(
                s.tokenIn,
                tokenOut,
                s.amountInMax + msg.value,
                s.callee,
                s.allowanceTarget,
                s.data,
                s.refundAddress
            );

        require(
            amountCredited >= s.amountOutMin,
            "not enough output from trade"
        );

        return amountCredited;
    }

    /************************************************
     * HELPERS
     ***********************************************/

    /**
     * @notice cancels all orders and finalizes the auction
     * @param auction the auction to cancel
     * @param epoch epoch id
     */
    function _cancel(AuctionStorage.Auction storage auction, uint64 epoch)
        internal
    {
        auction.totalPremiums = 0;
        _updateStatus(auction, AuctionStorage.Status.CANCELLED, epoch);
    }

    /**
     * @notice calculates the expected proceeds of the option if it has expired
     * @param epoch epoch id
     * @param size amount of contracts
     * @return true if the option has expired
     * @return the exercised amount
     */
    function _getExerciseAmount(
        AuctionStorage.Layout storage l,
        uint64 epoch,
        uint256 size
    ) private view returns (bool, uint256) {
        AuctionStorage.Auction storage auction = l.auctions[epoch];

        uint64 expiry = auction.expiry;
        int128 strike64x64 = auction.strike64x64;

        if (block.timestamp < expiry) return (false, 0);

        int128 spot64x64 = Pool.getPriceAfter64x64(expiry);
        uint256 amount;

        if (isCall && spot64x64 > strike64x64) {
            amount = spot64x64.sub(strike64x64).div(spot64x64).mulu(size);
        } else if (!isCall && strike64x64 > spot64x64) {
            uint256 value = strike64x64.sub(spot64x64).mulu(size);

            // converts the value to the base asset amount, this is particularly important where the
            // the decimals of the underlying are different from the base (e.g. wBTC/DAI)
            amount = OptionMath.toBaseTokenAmount(
                underlyingDecimals,
                baseDecimals,
                value
            );
        }

        return (true, amount);
    }

    /**
     * @notice removes the active unique order id from uoids mapping
     * @param l auction storage layout
     * @param epoch epoch id
     * @param orderId order id
     */
    function _removeUniqueOrderId(
        AuctionStorage.Layout storage l,
        uint64 epoch,
        uint128 orderId
    ) internal {
        EnumerableSet.UintSet storage uoids = l.uoids[msg.sender];

        unchecked {
            for (uint256 i; i < uoids.length(); ++i) {
                uint256 uoid = uoids.at(i);
                (, uint64 _epoch, uint128 _orderId) =
                    AuctionStorage._parseUniqueOrderId(uoid);

                if (
                    (orderId == 0 && _epoch == epoch) ||
                    (_orderId == orderId && _epoch == epoch)
                ) {
                    uoids.remove(uoid);
                }
            }
        }
    }

    function _updateStatus(
        AuctionStorage.Auction storage auction,
        AuctionStorage.Status status,
        uint64 epoch
    ) internal {
        auction.status = status;
        emit AuctionStatusSet(epoch, auction.status);
    }
}

