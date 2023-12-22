// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";
import "./PairInfoInterface.sol";
import "./LimitOrdersInterface.sol";
import "./CallbacksInterface.sol";

contract NarwhalTrading is Initializable, ReentrancyGuardUpgradeable {

    StorageInterface public storageT;
    PairInfoInterface public pairInfos;
    LimitOrdersInterface public limitOrders;

    uint public PRECISION;
    uint public MAX_SL_P;
    uint public MAX_GAIN_P;

    address public VaultFactory;

    uint public maxPosUSDT; // usdtDecimals (eg. 75000 * usdtDecimals)
    uint public limitOrdersTimelock; // block (eg. 30)
    uint public marketOrdersTimeout; // block (eg. 30)
    uint256 public timeLimit; //block

    bool public isDone;
    mapping(address => uint256) public orderExecutionTimeLimit;
    mapping(address => bool) public allowedToInteract;
    uint256 public tempSlippage;
    uint256 public tempSpreadReduction;
    uint256 public tempSL;
    bool public isLimitOrder;
    uint256 public tempOrderId;

    // Events
    event Done(bool done);

    event NumberUpdated(string name, uint value);

    event OrderExecutionData(
        address trader,
        uint pairIndex,
        uint positionSizeUSDT,
        uint openPrice,
        uint currentPrice,
        bool buy,
        uint leverage,
        uint256 openTime,
        uint256 closeTime);

    event OpenLimitPlaced(
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );
    event OpenLimitUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newPrice,
        uint newTp,
        uint newSl
    );
    event OpenLimitCanceled(
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    event TpUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newTp
    );
    event SlUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newSl
    );
    event SlUpdateInitiated(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newSl
    );

    event CouldNotCloseTrade(
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    event AllowedToInteractSet(address indexed sender, bool status);

    function initialize(
        StorageInterface _storageT,
        LimitOrdersInterface _limitOrders,
        PairInfoInterface _pairInfos,
        uint _maxPosUSDT,
        uint _limitOrdersTimelock,
        uint _marketOrdersTimeout
    ) public initializer {
        require(
            address(_storageT) != address(0) &&
                address(_pairInfos) != address(0) &&
                _maxPosUSDT > 0 &&
                _limitOrdersTimelock > 0 &&
                _marketOrdersTimeout > 0,
            "WRONG_PARAMS"
        );

        storageT = _storageT;
        pairInfos = _pairInfos;
        limitOrders = _limitOrders;

        PRECISION = 1e10;
        MAX_SL_P = 90; // -90% PNL
        MAX_GAIN_P = 900;
        timeLimit = 1;

        maxPosUSDT = _maxPosUSDT;
        limitOrdersTimelock = _limitOrdersTimelock;
        marketOrdersTimeout = _marketOrdersTimeout;
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier notContract() {
        if (allowedToInteract[msg.sender]) {} else {
            require(tx.origin == msg.sender);
        }

        _;
    }
    modifier notDone() {
        require(!isDone, "DONE");
        _;
    }

    // Manage params
    function setMaxPosUSDT(uint value) external onlyGov {
        require(value > 0, "VALUE_0");
        maxPosUSDT = value;

        emit NumberUpdated("maxPosUSDT", value);
    }

    function setLimitOrdersTimelock(uint value) external onlyGov {
        require(value > 0, "VALUE_0");
        limitOrdersTimelock = value;

        emit NumberUpdated("limitOrdersTimelock", value);
    }

    function setTimeLimit(uint256 _timeLimit) public onlyGov{
        require(_timeLimit < 5, "Time limit too high");
        timeLimit = _timeLimit;
    }

    function setAllowedToInteract(address _contract, bool _status) public {
        require(msg.sender == VaultFactory, "Not vault factory");
        allowedToInteract[_contract] = _status;
        emit AllowedToInteractSet(_contract, _status);
    }

    function setVaultFactory(address _VaultFactory) public onlyGov {
        require(_VaultFactory != address(0), "No dead address");
        VaultFactory = _VaultFactory;
    }

    function setMarketOrdersTimeout(uint value) external onlyGov {
        require(value > 0, "VALUE_0");
        marketOrdersTimeout = value;

        emit NumberUpdated("marketOrdersTimeout", value);
    }

    function done() external onlyGov {
        isDone = !isDone;

        emit Done(isDone);
    }

    // Execute limit order
    function executeLimitOrder(
        StorageInterface.LimitOrder orderType,
        address trader,
        uint pairIndex,
        uint index,
        bytes[] calldata updateData
    ) external notContract notDone nonReentrant {
        address sender = msg.sender;
        uint256 openTimestamp;
        uint256 price;
        StorageInterface.Trade memory t;
        require(block.number > orderExecutionTimeLimit[trader] + (timeLimit),"Wait a bit more");
        if (orderType == StorageInterface.LimitOrder.OPEN) {
            require(
                storageT.hasOpenLimitOrder(trader, pairIndex, index),
                "NO_LIMIT"
            );
        } else {
            t = storageT.openTrades(trader, pairIndex, index);

            require(t.leverage > 0, "NO_TRADE");
            
            if (orderType == StorageInterface.LimitOrder.LIQ) {
                uint liqPrice = getTradeLiquidationPrice(t);

                require(
                    t.sl == 0 || (t.buy ? liqPrice > t.sl : liqPrice < t.sl),
                    "HAS_SL"
                );
            } else {
                require(
                    orderType != StorageInterface.LimitOrder.SL || t.sl > 0,
                    "NO_SL"
                );
                require(
                    orderType != StorageInterface.LimitOrder.TP || t.tp > 0,
                    "NO_TP"
                );
            }
        }
        
        LimitOrdersInterface.TriggeredLimitId
            memory triggeredLimitId = LimitOrdersInterface.TriggeredLimitId(
                trader,
                pairIndex,
                index,
                orderType
            );

        if (
            !limitOrders.triggered(triggeredLimitId) ||
            limitOrders.timedOut(triggeredLimitId)
        ) {
            uint leveragedPosUSDT;

            if (orderType == StorageInterface.LimitOrder.OPEN) {
                StorageInterface.OpenLimitOrder memory l = storageT
                    .getOpenLimitOrder(trader, pairIndex, index);

                leveragedPosUSDT = l.positionSize * l.leverage;

                (uint priceImpactP, ) = pairInfos.getTradePriceImpact(
                    0,
                    l.pairIndex,
                    l.buy,
                    leveragedPosUSDT
                );

                require(
                    priceImpactP * l.leverage <=
                        pairInfos.maxNegativePnlOnOpenP(),
                    "PRICE_IMPACT_TOO_HIGH"
                );
                t.trader = sender;
                t.pairIndex = pairIndex;
                t.index = index;
                t.leverage = l.leverage;
                t.positionSizeUSDT = l.positionSize;
            } else {
                leveragedPosUSDT =
                    (t.initialPosToken *
                        storageT
                            .openTradesInfo(trader, pairIndex, index)
                            .tokenPriceUSDT *
                        t.leverage) /
                    PRECISION;
            }

            isLimitOrder = true;
            tempOrderId = storageT.priceAggregator().beforeGetPriceLimit(t);
            storageT.storePendingLimitOrder(
                StorageInterface.PendingLimitOrder(
                    sender,
                    trader,
                    pairIndex,
                    index,
                    orderType
                ),
                tempOrderId
            );

            openTimestamp = storageT.openTimestamp(trader, pairIndex, index);
            (,price) = storageT.priceAggregator().getPrice(
                orderType == StorageInterface.LimitOrder.OPEN
                    ? AggregatorInterfaceV6_2.OrderType.LIMIT_OPEN
                    : AggregatorInterfaceV6_2.OrderType.LIMIT_CLOSE,
                updateData,
                t
            );

            isLimitOrder = false;
            delete tempOrderId;

            limitOrders.storeFirstToTrigger(triggeredLimitId, sender);
        } else {
            limitOrders.storeTriggerSameBlock(triggeredLimitId, sender);
        }

        bool closeSuccessful = storageT.tempTradeStatus(trader,pairIndex,index);
        if (closeSuccessful) {
            emit OrderExecutionData(t.trader,t.pairIndex,t.positionSizeUSDT, t.openPrice,price,t.buy,t.leverage,openTimestamp,block.timestamp);
        }

    }

    // Open new trade (MARKET/LIMIT)
    function openTrade(
        StorageInterface.Trade memory t,
        LimitOrdersInterface.OpenLimitOrderType orderType, // LEGACY => market
        uint spreadReductionId,
        uint slippageP, // for market orders only
        bytes[] calldata updateData
    ) external notContract notDone nonReentrant {
        PairsStorageInterface pairsStored = storageT
            .priceAggregator()
            .pairsStorage();

        require(block.number > orderExecutionTimeLimit[msg.sender] + (timeLimit),"Wait a bit more");
        require(
            storageT.openTradesCount(t.trader, t.pairIndex) +
                storageT.pendingMarketOpenCount(t.trader, t.pairIndex) +
                storageT.openLimitOrdersCount(t.trader, t.pairIndex) <
                storageT.maxTradesPerPair(),
            "MAX_TRADES_PER_PAIR"
        );

        require(
            storageT.pendingOrderIdsCount(t.trader) <
                storageT.maxPendingMarketOrders(),
            "MAX_PENDING_ORDERS"
        );

        require(t.positionSizeUSDT <= maxPosUSDT, "ABOVE_MAX_POS");
        require(
            t.positionSizeUSDT * t.leverage >=
                pairsStored.pairMinLevPosUSDT(t.pairIndex),
            "BELOW_MIN_POS"
        );

        require(
            t.leverage > 0 &&
                t.leverage >= pairsStored.pairMinLeverage(t.pairIndex) &&
                t.leverage <= pairsStored.pairMaxLeverage(t.pairIndex),
            "LEVERAGE_INCORRECT"
        );

        require(
            t.tp == 0 || (t.buy ? t.tp > t.openPrice : t.tp < t.openPrice),
            "WRONG_TP"
        );

        require(
            t.sl == 0 || (t.buy ? t.sl < t.openPrice : t.sl > t.openPrice),
            "WRONG_SL"
        );

        (uint priceImpactP, ) = pairInfos.getTradePriceImpact(
            0,
            t.pairIndex,
            t.buy,
            t.positionSizeUSDT * t.leverage
        );

        require(
            priceImpactP * t.leverage <= pairInfos.maxNegativePnlOnOpenP(),
            "PRICE_IMPACT_TOO_HIGH"
        );

        storageT.transferUSDT(
            msg.sender,
            address(storageT),
            t.positionSizeUSDT
        );

        if (orderType != LimitOrdersInterface.OpenLimitOrderType.LEGACY) {
            uint index = storageT.firstEmptyOpenLimitIndex(
                t.trader,
                t.pairIndex
            );

            storageT.storeOpenLimitOrder(
                StorageInterface.OpenLimitOrder(
                    t.trader,
                    t.pairIndex,
                    index,
                    t.positionSizeUSDT,
                    spreadReductionId > 0
                        ? storageT.spreadReductionsP(spreadReductionId - 1)
                        : 0,
                    t.buy,
                    t.leverage,
                    t.tp,
                    t.sl,
                    t.openPrice,
                    t.openPrice,
                    block.number,
                    0
                )
            );

            limitOrders.setOpenLimitOrderType(
                t.trader,
                t.pairIndex,
                index,
                orderType
            );
            emit OpenLimitPlaced(t.trader, t.pairIndex, index);
        } else {
            tempSlippage = slippageP;
            tempSpreadReduction = spreadReductionId > 0
                ? storageT.spreadReductionsP(spreadReductionId - 1)
                : 0;

            storageT.priceAggregator().getPrice(
                AggregatorInterfaceV6_2.OrderType.MARKET_OPEN,
                updateData,
                t
            );
            tempSlippage = 0;
            tempSpreadReduction = 0;
        }
        orderExecutionTimeLimit[msg.sender] = block.number;
    }

    // Close trade (MARKET)
    function closeTradeMarket(
        uint pairIndex,
        uint index,
        bytes[] calldata updateData
    ) external notContract notDone nonReentrant {
        address sender = msg.sender;
        require(block.number > orderExecutionTimeLimit[sender] + (timeLimit),"Wait a bit more");
        StorageInterface.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        StorageInterface.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );

        require(
            storageT.pendingOrderIdsCount(sender) <
                storageT.maxPendingMarketOrders(),
            "MAX_PENDING_ORDERS"
        );

        require(!i.beingMarketClosed, "ALREADY_BEING_CLOSED");
        require(t.leverage > 0, "NO_TRADE");
        uint256 openTime = storageT.openTimestamp(t.trader,t.pairIndex,t.index);
        (uint orderId,uint256 price) = storageT.priceAggregator().getPrice(
            AggregatorInterfaceV6_2.OrderType.MARKET_CLOSE,
            updateData,
            t
        );
        orderExecutionTimeLimit[msg.sender] = block.number;
        emit OrderExecutionData(t.trader,t.pairIndex,t.positionSizeUSDT, t.openPrice,price,t.buy,t.leverage,openTime,block.timestamp);
    }

    // Manage limit order (OPEN)
    function updateOpenLimitOrder(
        uint pairIndex,
        uint index,
        uint price, // PRECISION
        uint tp,
        uint sl
    ) external notContract notDone {
        address sender = msg.sender;

        require(
            storageT.hasOpenLimitOrder(sender, pairIndex, index),
            "NO_LIMIT"
        );

        require(block.number > orderExecutionTimeLimit[sender] + (timeLimit),"Wait a bit more");

        StorageInterface.OpenLimitOrder memory o = storageT.getOpenLimitOrder(
            sender,
            pairIndex,
            index
        );

        require(
            block.number - o.block >= limitOrdersTimelock,
            "LIMIT_TIMELOCK"
        );

        require(tp == 0 || (o.buy ? tp > price : tp < price), "WRONG_TP");

        require(sl == 0 || (o.buy ? sl < price : sl > price), "WRONG_SL");

        o.minPrice = price;
        o.maxPrice = price;

        o.tp = tp;
        o.sl = sl;

        storageT.updateOpenLimitOrder(o);
        orderExecutionTimeLimit[sender] = block.number;
        emit OpenLimitUpdated(sender, pairIndex, index, price, tp, sl);
    }

    function cancelOpenLimitOrder(
        uint pairIndex,
        uint index
    ) external notContract notDone {
        address sender = msg.sender;

        require(
            storageT.hasOpenLimitOrder(sender, pairIndex, index),
            "NO_LIMIT"
        );

        StorageInterface.OpenLimitOrder memory o = storageT.getOpenLimitOrder(
            sender,
            pairIndex,
            index
        );

        require(
            block.number - o.block >= limitOrdersTimelock,
            "LIMIT_TIMELOCK"
        );

        storageT.unregisterOpenLimitOrder(sender, pairIndex, index);
        storageT.transferUSDT(address(storageT), sender, o.positionSize);

        emit OpenLimitCanceled(sender, pairIndex, index);
    }

    // Manage limit order (TP/SL)
    function updateTp(
        uint pairIndex,
        uint index,
        uint newTp,
        bytes[] calldata updateData
    ) external notContract notDone {
        address sender = msg.sender;
        
        StorageInterface.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );
        require(t.leverage > 0, "NO_TRADE");
        StorageInterface.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );
        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();
        uint256 price = aggregator.updatePriceFeed(
            t.pairIndex,
            updateData
        );
        uint256 maxtp = maxTP(t.openPrice, t.leverage, t.buy);

        // Ensure newTp is between the current price and the maximum take profit.
        require(
            t.buy ? price <= newTp && newTp <= maxtp : maxtp <= newTp && newTp <= price,
            "WRONG_TP"
        );
        
        require(
            block.number - i.tpLastUpdated >= limitOrdersTimelock,
            "LIMIT_TIMELOCK"
        );

        storageT.updateTp(sender, pairIndex, index, newTp);
        emit TpUpdated(sender, pairIndex, index, newTp);
    }

    function maxTP(
        uint openPrice,
        uint leverage,
        bool buy) public view returns (uint256) {

        uint tpDiff = (openPrice * MAX_GAIN_P) / leverage / 100;

        return buy ? openPrice + tpDiff : tpDiff <= openPrice ? openPrice - tpDiff : 0;
    }

    function updateSl(
        uint pairIndex,
        uint index,
        uint newSl,
        bytes[] calldata updateData
    ) external notContract notDone {
        address sender = msg.sender;
        StorageInterface.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        StorageInterface.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );

        require(t.leverage > 0, "NO_TRADE");

        uint maxSlDist = (t.openPrice * MAX_SL_P) / 100 / t.leverage;
        require(
            newSl == 0 ||
                (
                    t.buy
                        ? newSl >= t.openPrice - maxSlDist
                        : newSl <= t.openPrice + maxSlDist
                ),
            "SL_TOO_BIG"
        );

        require(
            block.number - i.slLastUpdated >= limitOrdersTimelock,
            "LIMIT_TIMELOCK"
        );

        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();

        if (
            newSl == 0 ||
            !aggregator.pairsStorage().guaranteedSlEnabled(pairIndex)
        ) {
            storageT.updateSl(sender, pairIndex, index, newSl);

            emit SlUpdated(sender, pairIndex, index, newSl);
        } else {
            tempSL = newSl;
            (uint orderId, ) = aggregator.getPrice(
                AggregatorInterfaceV6_2.OrderType.UPDATE_SL,
                updateData,
                t
            );
            delete tempSL;

            emit SlUpdateInitiated(orderId, sender, pairIndex, index, newSl);
        }
    }

    // Avoid stack too deep error in executeLimitOrder
    function getTradeLiquidationPrice(
        StorageInterface.Trade memory t
    ) private view returns (uint) {
        return
            pairInfos.getTradeLiquidationPrice(
                t.trader,
                t.pairIndex,
                t.index,
                t.openPrice,
                t.buy,
                (t.initialPosToken *
                    storageT
                        .openTradesInfo(t.trader, t.pairIndex, t.index)
                        .tokenPriceUSDT) / PRECISION,
                t.leverage
            );
    }
}

