// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Store.sol";
import "./ChainlinkFeed.sol";
import "./API3.sol";
import "./IRouter.sol";
import "./IPool.sol";

contract TradeV2 {
    uint256 public BPS_DIVIDER = 10000;
    uint256 public size = 10000;
    uint256 public constant UNIT = 10 ** 18;

    uint256 public minMargin = 100000000000000;
    uint256 public minLeverage = 5;
    uint256 public maxLeverage = 50;

    address public gov;
    address public owner;
    address public router;
    uint256 public fee = 80;

    Chainlink public chainlink;
    DataStore public Store;
    DataFeedReader public api3Feed;

    uint256 public liquidationThreshold = 8000; // In bps. 8000 = 80%. 4 bytes
    address public treasury;

    int256 public fundingTracker;
    uint256 public utilizationMultiplier = 100; // in bps

    // Events
    event PositionCreated(
        uint256 orderId,
        address indexed user,
        address indexed currency,
        uint256 marketId,
        uint256 entry,
        bool isLong,
        uint256 leverage,
        uint256 orderType,
        uint256 margin,
        uint256 takeProfit,
        uint256 stopLoss,
        bool isActive
    );

    event AddMargin(
        uint256 indexed id,
        address indexed user,
        uint256 margin,
        uint256 newMargin,
        uint256 newLeverage
    );

    event ReduceMargin(
        uint256 indexed id,
        address indexed user,
        uint256 margin,
        uint256 newMargin,
        uint256 newLeverage
    );

    event FeeGenerated(
        uint256 amount,
        address indexed currency,
        uint256 timestamp
    );

    event OpenOrder(
        uint256 indexed positionId,
        address indexed user,
        uint256 indexed marketId
    );

    event ClosePosition(
        uint256 orderId,
        address user,
        address currency,
        uint256 marketId,
        bool isLong,
        uint256 leverage,
        uint256 margin,
        uint256 takeProfit,
        uint256 stopLoss,
        bool isActive,
        uint256 pnl,
        uint256 earning,
        bool isLiquidated
    );

    event LiquidatedOrder(
        uint256 orderId,
        address user,
        address currency,
        uint256 marketId,
        bool isLong,
        uint256 margin,
        uint256 takeProfit,
        uint256 stopLoss,
        uint256 pnl,
        uint256 earning
    );

    event OrderCancelled(uint256 indexed orderId, address indexed user);

    constructor() {
        gov = msg.sender;
        owner = msg.sender;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function setLiquidation(uint256 t) external onlyOwner {
        liquidationThreshold = t;
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
        treasury = IRouter(router).treasury();
    }

    function setUtilizaitonMultiplier(uint256 val) external onlyOwner {
        utilizationMultiplier = val;
    }

    function link(address _store, address _feed) external onlyOwner {
        Store = DataStore(_store);
        api3Feed = DataFeedReader(_feed);
    }

    function _transferIn(address currency, uint256 amount) internal {
        if (amount == 0 || currency == address(0)) return;
        IERC20(currency).transferFrom(msg.sender, address(this), amount);
    }

    function treasuryTransfer(address currency, uint256 amount) internal {
        if (amount == 0 || currency == address(0)) return;
        IERC20(currency).transferFrom(msg.sender, treasury, amount);
    }

    function _transferOut(
        address currency,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0 || currency == address(0) || to == address(0)) return;
        IERC20(currency).transfer(to, amount);
    }

    function feeCharges(
        uint256 margin
    ) private view returns (uint256, uint256) {
        uint256 charge = (fee * margin) / 10000;
        uint256 currentMargin = margin - charge;
        return (charge, currentMargin);
    }

    uint256 treasuryShare = 3000;

    function poolShare(uint256 amount) public view returns (uint256) {
        uint256 share = (treasuryShare * amount) / 10000;
        return share;
    }

    function updateShare(uint256 amount) external onlyOwner {
        treasuryShare = amount;
    }

    function updateMaxLeverage(uint256 amount) external onlyOwner {
        maxLeverage = amount;
    }

    /// @dev Submitted Pyth price is bound by the Chainlink price
    function _boundPriceWithChainlink(
        uint256 maxDeviation,
        uint256 api3prcie,
        uint256 price
    ) internal view returns (bool) {
        if (api3prcie == 0 || maxDeviation == 0) return true;
        if (
            price >= (api3prcie * (BPS_DIVIDER - maxDeviation)) / BPS_DIVIDER &&
            price <= (api3prcie * (BPS_DIVIDER + maxDeviation)) / BPS_DIVIDER
        ) {
            return true;
        }
        return false;
    }

    function submitTrade(
        DataStore.OrderData memory dataEntry,
        uint256 marketId,
        uint256 leverage,
        address currency
    ) external {
        require(IRouter(router).isSupportedCurrency(currency), "!currency");
        require(dataEntry.price > 0, "!limit price");
        require(dataEntry.leverage <= maxLeverage);
        require(
            dataEntry.orderType == 0 || dataEntry.orderType == 1,
            "!limit / market"
        );
        DataStore.MarketData memory market = Store.getMarket(marketId);

        uint256 poolUtilization = getUtilization(currency);

        require(poolUtilization < 10 ** 4, "!utilization");

        (uint256 cPrice, ) = _getAPI3Feed(market.feed);

        require(cPrice > 0, "!price feed");
        require(dataEntry.margin > minMargin, "!minMargin");
        require(leverage >= minLeverage, "!leverage");

        (uint256 feeCharge, uint256 currentMargin) = feeCharges(
            dataEntry.margin
        );

        emit FeeGenerated(feeCharge, dataEntry.currency, block.timestamp);

        treasuryTransfer(currency, feeCharge);
        _transferIn(currency, currentMargin);

        // market entry
        uint256 orderId;
        if (dataEntry.orderType == 0) {
            dataEntry.price = cPrice;
            dataEntry.margin = currentMargin;
            dataEntry.isActive = true;
            orderId = Store.addOrder(dataEntry);
            emit OpenOrder(orderId, dataEntry.user, marketId);
        }

        // limit entry
        if (dataEntry.orderType == 1) {
            dataEntry.margin = currentMargin;
            dataEntry.isActive = false;
            orderId = Store.addOrder(dataEntry);
            emit OpenOrder(orderId, dataEntry.user, marketId);
        }

        uint256 amount = dataEntry.margin * leverage;
        Store.incrementOpenInterest(marketId, amount, dataEntry.isLong);

        IncrementPoolOpenInterest(amount, currency, false);

        emit PositionCreated(
            orderId,
            msg.sender,
            dataEntry.currency,
            marketId,
            cPrice,
            dataEntry.isLong,
            dataEntry.leverage,
            dataEntry.orderType,
            currentMargin,
            dataEntry.takeProfit,
            dataEntry.stopLoss,
            dataEntry.isActive
        );
    }

    function processLimitOrders(uint256[] calldata orderIds) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 id = orderIds[i];
            DataStore.OrderData memory order = Store.getOrder(id);
            DataStore.MarketData memory market = Store.getMarket(
                order.marketId
            );
            (uint256 currentPrice, ) = _getAPI3Feed(market.feed);
            if (order.isLong == true && order.price >= currentPrice) {
                Store.activateLimitOrders(id);
            }
            if (order.isLong == false && order.price <= currentPrice) {
                Store.activateLimitOrders(id);
            }
        }
    }

    function processLimitOrdersTest(
        uint256[] calldata orderIds,
        uint256 price
    ) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 id = orderIds[i];
            DataStore.OrderData memory order = Store.getOrder(id);
            if (order.isLong == true && order.price >= price) {
                Store.activateLimitOrders(id);
            }
            if (order.isLong == false && order.price <= price) {
                Store.activateLimitOrders(id);
            }
        }
    }

    function closeTrade(uint256 orderId) public {
        DataStore.OrderData memory order = Store.getOrder(orderId);
        require(order.user != address(0), "!address");
        require(order.user == msg.sender, "!user");
        require(order.margin > 0, "!margin");

        (uint256 earning, uint256 pnl, bool isNegative) = getEarning(
            order.orderId
        );
        uint256 threshold = (order.margin * liquidationThreshold) / BPS_DIVIDER;

        address pool = IRouter(router).getPool(order.currency);

        bool liquidated = false;

        if (isNegative == true) {
            if (earning >= threshold) {
                liquidated = true;
            }

            if (earning <= order.margin) {
                uint256 amount = order.margin - earning;
                _transferOut(order.currency, order.user, amount);
                _transferOut(order.currency, treasury, earning);
            } else {
                _transferOut(order.currency, treasury, order.margin);
            }

            Store.removeOrder(orderId);

            emit ClosePosition(
                order.orderId,
                order.user,
                order.currency,
                order.marketId,
                order.isLong,
                order.leverage,
                order.margin,
                order.takeProfit,
                order.stopLoss,
                order.isActive,
                pnl,
                earning,
                liquidated
            );

            Store.decreaseOpenIntrest(
                order.marketId,
                order.margin * order.leverage,
                order.isLong
            );
            IncrementPoolOpenInterest(
                order.margin * order.leverage,
                order.currency,
                true
            );
        } else {
            _transferOut(order.currency, order.user, order.margin);
            IPool(pool).creditUserProfit(order.user, earning);
            Store.removeOrder(orderId);

            emit ClosePosition(
                order.orderId,
                order.user,
                order.currency,
                order.marketId,
                order.isLong,
                order.leverage,
                order.margin,
                order.takeProfit,
                order.stopLoss,
                order.isActive,
                pnl,
                earning,
                liquidated
            );

            Store.decreaseOpenIntrest(
                order.marketId,
                order.margin * order.leverage,
                order.isLong
            );
            IncrementPoolOpenInterest(
                order.margin * order.leverage,
                order.currency,
                true
            );
        }
    }

    function closeTradeTest(uint256 orderId) public {
        DataStore.OrderData memory order = Store.getOrder(orderId);
        require(order.user == msg.sender, "!user");
        require(order.margin > 0, "!margin");

        (uint256 earning, , bool isNegative) = getEarning(order.orderId);
        address pool = IRouter(router).getPool(order.currency);


        if (isNegative == true) {
            if (earning <= order.margin) {
                uint256 amount = order.margin - earning;
                _transferOut(order.currency, order.user, amount);
                _transferOut(order.currency, treasury, earning);
            } else {
                _transferOut(order.currency, treasury, order.margin);
            }
        } else {
            _transferOut(order.currency, order.user, order.margin);
            IPool(pool).creditUserProfit(order.user, earning);
        }
    }

    function closeMultipleTrades(uint256[] calldata orderIds) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            closeTrade(orderIds[i]);
        }
    }

    // Increasing margin reduces leverage/risk
    function addMargin(uint256 id, uint256 amount, address currency) external {
        DataStore.OrderData memory order = Store.getOrder(id);
        require(msg.sender == order.user, "!user");
        require(amount > minMargin, "!minMargin");

        uint256 poolUtilization = getUtilization(currency);
        require(poolUtilization < 10 ** 4, "!utilization");

        (uint256 feeCharge, uint256 currentMargin) = feeCharges(amount);

        emit FeeGenerated(feeCharge, order.currency, block.timestamp);

        _transferIn(currency, feeCharge);
        Store.addMargin(id, currentMargin);
    }

    function processCompletedTrades(uint256[] memory orderIds) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 id = orderIds[i];
            DataStore.OrderData memory order = Store.getOrder(id);
            DataStore.MarketData memory market = Store.getMarket(
                order.marketId
            );
            (uint256 currentPrice, ) = _getAPI3Feed(market.feed);
            require(order.takeProfit > 0, "!tp");
            require(order.stopLoss > 0, "!sl");
            // crossed tp
            if (order.isLong == true && order.takeProfit >= currentPrice) {
                closeTrade(id);
            }

            if (order.isLong == false && order.takeProfit <= currentPrice) {
                closeTrade(id);
            }

            // crossed sl
            if (order.isLong == true && currentPrice <= order.stopLoss) {
                closeTrade(id);
            }

            if (order.isLong == false && order.stopLoss >= currentPrice) {
                closeTrade(id);
            }
        }
    }

    function processCompletedTradesTest(
        uint256[] memory orderIds,
        uint256 cPrice
    ) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 id = orderIds[i];
            DataStore.OrderData memory order = Store.getOrder(id);
            uint256 currentPrice = cPrice;
            require(order.takeProfit > 0, "!tp");
            require(order.stopLoss > 0, "!sl");

            // crossed tp
            // long
            if (order.isLong == true && order.takeProfit >= currentPrice) {
                Store.removeOrder(id);
                break;
            }

            // shorts
            if (order.isLong == false && order.takeProfit <= currentPrice) {
                Store.removeOrder(id);
                break;
            }

            // crossed sl
            // long
            if (order.isLong == true && currentPrice <= order.stopLoss) {
                Store.removeOrder(id);
                break;
            }

            // shorts
            if (order.isLong == false && order.stopLoss >= currentPrice) {
                Store.removeOrder(id);
                break;
            }
        }
    }

    // Data Collection

    function getOrder(
        uint256 id
    ) external view returns (DataStore.OrderData memory _orders) {
        DataStore.OrderData memory order = Store.getOrder(id);
        return order;
    }

    function getMarket(
        uint256 id
    ) external view returns (DataStore.MarketData memory market) {
        DataStore.MarketData memory data = Store.getMarket(id);
        return data;
    }

    function getUtilization(address token) public view returns (uint256) {
        address pool = IRouter(router).getPool(token);
        (uint256 poolOI, uint256 multiplier) = IPool(pool).getPoolOI();
        uint256 utilization = (poolOI * multiplier) /
            IERC20(token).balanceOf(pool);
        return utilization;
    }

    function getAllOrders()
        external
        view
        returns (DataStore.OrderData[] memory _orders)
    {
        DataStore.OrderData[] memory orders = Store.getOrders();
        return orders;
    }

    function getUserOrdersFromStore(
        address user
    ) public view returns (DataStore.OrderData[] memory _users) {
        return Store.getUserOrders(user);
    }

    function _getPnL(
        uint256 marketId,
        bool isLong,
        uint256 price,
        uint256 positionPrice,
        uint256 size,
        int256 fundingTracker
    ) internal view returns (int256 pnl, bool isNegative, int256 fundingFee) {
        if (price == 0 || positionPrice == 0 || size == 0) return (0, false, 0);

        int256 currentFundingTracker = Store.getFundingTracker(marketId);
        fundingFee =
            (int256(size) * (currentFundingTracker - fundingTracker)) /
            (int256(BPS_DIVIDER) * int256(UNIT)); // funding tracker is in UNIT * bps

        if (isLong) {
            if (price >= positionPrice) {
                pnl =
                    (int256(size) * (int256(price) - int256(positionPrice))) /
                    int256(positionPrice);
                isNegative = false;
                pnl -= fundingFee; // positive = longs pay, negative = longs receive
                return (pnl, isNegative, fundingFee);
            } else {
                pnl =
                    (int256(size) * (int256(price) - int256(positionPrice))) /
                    int256(positionPrice);
                isNegative = true;
                pnl -= fundingFee; // positive = longs pay, negative = longs receive
                return (pnl, isNegative, fundingFee);
            }
        } else {
            pnl =
                (int256(size) * (int256(positionPrice) - int256(price))) /
                int256(positionPrice);

            if (price >= positionPrice) {
                pnl =
                    (int256(size) * (int256(price) - int256(positionPrice))) /
                    int256(positionPrice);
                isNegative = false;
                pnl += fundingFee; // positive = longs pay, negative = longs receive
                return (pnl, isNegative, fundingFee);
            } else {
                pnl =
                    (int256(size) * (int256(price) - int256(positionPrice))) /
                    int256(positionPrice);
                isNegative = true;
                pnl += fundingFee;
                return (pnl, isNegative, fundingFee);
            }
        }
    }

    function getEarning(
        uint256 id
    ) public view returns (uint256 earning, uint256 pnl, bool) {
        DataStore.OrderData memory order = Store.getOrder(id);

        DataStore.MarketData memory market = Store.getMarket(order.marketId);

        if (order.isActive != true) {
            return (0, 0, false);
        }
        (uint256 currentPrice, ) = _getAPI3Feed(market.feed);

        (int256 increment, bool isNegative, ) = _getPnL(
            order.marketId,
            order.isLong,
            currentPrice,
            order.price,
            size,
            fundingTracker
        );

        if (isNegative == true) {
            increment = increment * -1;
            pnl = uint256(increment) * order.leverage;
        } else {
            pnl = uint256(increment) * order.leverage;
        }

        earning = (pnl * order.margin) / BPS_DIVIDER;
        return (earning, pnl, isNegative);
    }

    function liquidateOrders(uint256 orderId) public {
        DataStore.OrderData memory order = Store.getOrder(orderId);
        require(order.user != address(0), "!null address");
        // gets pnl and earning
        (uint256 earning, uint256 pnl, bool isNegative) = getEarning(orderId);

        uint256 threshold = (order.margin * liquidationThreshold) / BPS_DIVIDER;
        address currency = order.currency;
        if (isNegative == true && earning >= threshold) {
            _transferOut(currency, order.user, order.margin - threshold);
            Store.removeOrder(orderId);
            emit LiquidatedOrder(
                order.orderId,
                order.user,
                order.currency,
                order.marketId,
                order.isLong,
                order.margin,
                order.takeProfit,
                order.stopLoss,
                pnl,
                earning
            );
        }
    }

    function LiquidatebleOrders(uint256[] memory orderIds) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 id = orderIds[i];
            DataStore.OrderData memory order = Store.getOrder(id);
            require(order.user != address(0), "!user");
            liquidateOrders(order.orderId);
        }
    }

    function getUserPositionsWithUpls(
        address user
    )
        external
        view
        returns (DataStore.OrderData[] memory _positions, int256[] memory _upls)
    {
        _positions = getUserOrdersFromStore(user);
        uint256 length = _positions.length;
        _upls = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
            DataStore.OrderData memory position = _positions[i];

            DataStore.MarketData memory market = Store.getMarket(
                position.marketId
            );

            // uint256 chainlinkPrice = _getChainlinkPrice(market.feed);
            (uint256 cPrice, ) = _getAPI3Feed(market.feed);

            if (cPrice == 0) continue;

            (int256 pnl, , ) = _getPnL(
                position.marketId,
                position.isLong,
                cPrice,
                position.price,
                size,
                fundingTracker
            );
            _upls[i] = pnl;
        }

        return (_positions, _upls);
    }

    function getOrderUPL(
        uint256 id
    ) public view returns (int256 upl, bool isNegative) {
        DataStore.OrderData memory position = Store.getOrder(id);
        DataStore.MarketData memory market = Store.getMarket(position.marketId);
        (uint256 cPrice, ) = _getAPI3Feed(market.feed);
        if (position.isActive == false) {
            return (0, false);
        }
        (int256 pnl, bool booValue, ) = _getPnL(
            position.marketId,
            position.isLong,
            cPrice,
            position.price,
            size,
            fundingTracker
        );
        return (pnl, booValue);
    }

    function getOILong(uint256 marketId) external view returns (uint256) {
        return Store.getOpenIntrestLong(marketId);
    }

    function getOIShort(uint256 marketId) external view returns (uint256) {
        return Store.getOpenIntrestShort(marketId);
    }

    function IncrementPoolOpenInterest(
        uint amount,
        address currency,
        bool isDecrease
    ) private {
        address pool = IRouter(router).getPool(currency);
        IPool(pool).updateOpenInterest(amount, isDecrease);
    }

    function _updateFundingTracker(uint256 marketId) internal {
        uint256 lastUpdated = Store.getFundingLastUpdated(marketId);
        uint256 _now = block.timestamp;

        if (lastUpdated == 0) {
            Store.setFundingLastUpdated(marketId, _now);
            return;
        }

        if (lastUpdated + Store.fundingInterval() > _now) return;

        int256 fundingIncrement = getAccruedFunding(marketId, 0); // in UNIT * bps
        if (fundingIncrement == 0) return;
        Store.updateFundingTracker(marketId, fundingIncrement);
        Store.setFundingLastUpdated(marketId, _now);
    }

    function getAccruedFunding(
        uint256 marketId,
        uint256 intervals
    ) public view returns (int256) {
        if (intervals == 0) {
            intervals =
                (block.timestamp - Store.getFundingLastUpdated(marketId)) /
                Store.fundingInterval();
        }

        if (intervals == 0) return 0;

        uint256 OILong = Store.getOpenIntrestLong(marketId);
        uint256 OIShort = Store.getOpenIntrestShort(marketId);

        if (OIShort == 0 && OILong == 0) return 0;

        uint256 OIDiff = OIShort > OILong ? OIShort - OILong : OILong - OIShort;
        uint256 yearlyFundingFactor = Store.getFundingFactor(marketId); // in bps
        // intervals = hours since fundingInterval = 1 hour
        uint256 accruedFunding = (UNIT *
            yearlyFundingFactor *
            OIDiff *
            intervals) / (24 * 365 * (OILong + OIShort)); // in UNIT * bps

        if (OILong > OIShort) {
            // Longs pay shorts. Increase funding tracker.
            return int256(accruedFunding);
        } else {
            // Shorts pay longs. Decrease funding tracker.
            return -1 * int256(accruedFunding);
        }
    }

    // Data Request

    function _getChainlinkPrice(address feed) public view returns (uint256) {
        if (feed == address(0)) return 0;

        (, int256 price, , uint256 timeStamp, ) = AggregatorV3Interface(feed)
            .latestRoundData();

        if (price <= 0 || timeStamp == 0) return 0;

        uint8 decimals = AggregatorV3Interface(feed).decimals();

        uint256 feedPrice;
        if (decimals != 8) {
            feedPrice = (uint256(price) * 10 ** 8) / 10 ** decimals;
        } else {
            feedPrice = uint256(price);
        }

        return feedPrice;
    }

    function _getAPI3Feed(address feed) public view returns (uint256, uint256) {
        (int224 value, uint256 timestamp) = api3Feed.readDataFeed(feed);

        uint256 dataValue = uint224(value);
        return (dataValue, timestamp);
    }

    function getChainlinkPrice(
        uint256 marketId
    ) external view returns (uint256) {
        DataStore.MarketData memory market = Store.getMarket(marketId);
        return _getChainlinkPrice(market.feed);
    }

    function getAPI3Feed(uint256 marketId) external view returns (uint256) {
        DataStore.MarketData memory market = Store.getMarket(marketId);
        (uint256 data, ) = _getAPI3Feed(market.feed);
        return data;
    }

    // Modifiers

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
}

