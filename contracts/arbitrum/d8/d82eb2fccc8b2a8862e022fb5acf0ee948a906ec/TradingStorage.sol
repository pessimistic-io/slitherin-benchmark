// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./EnumerableSet.sol";
import "./AggregatorInterface.sol";
import "./PoolInterface.sol";
import "./PausableInterface.sol";
import "./PairInfoInterface.sol";

contract TradingStorage is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.UintSet;

    // Constants
    uint public PRECISION;
    address public USDT;

    // Contracts (updatable)
    AggregatorInterface public priceAggregator;
    PairInfoInterface public pairInfos;
    PoolInterface public pool;
    address public trading;
    address public callbacks;

    address public vault;
    // Trading variables
    uint public maxTradesPerPair;
    uint public maxPendingMarketOrders;
    uint[5] public spreadReductionsP; // %

    // Gov (updatable)
    address public gov;
    address public pendingGov;

    mapping(uint256 => address) public keeperForOrder;

    // Enums
    enum LimitOrder {
        TP,
        SL,
        LIQ,
        OPEN
    }
    
    // Events
    struct Trade {
        address trader;
        uint pairIndex;
        uint index;
        uint initialPosToken; // usdtDecimals
        uint positionSizeUSDT; // usdtDecimals
        uint openPrice; // PRECISION
        bool buy;
        uint leverage;
        uint tp; // PRECISION
        uint sl;
    }
    struct TradeInfo {
        uint tokenId;
        uint tokenPriceUSDT; // PRECISION
        uint openInterestUSDT; // usdtDecimals
        uint tpLastUpdated;
        uint slLastUpdated;
        bool beingMarketClosed;
    }
    struct OpenLimitOrder {
        address trader;
        uint pairIndex;
        uint index;
        uint positionSize; // usdtDecimals
        uint spreadReductionP;
        bool buy;
        uint leverage;
        uint tp; // PRECISION (%)
        uint sl; // PRECISION (%)
        uint minPrice; // PRECISION
        uint maxPrice; // PRECISION
        uint block;
        uint tokenId;
    }
    struct PendingMarketOrder {
        Trade trade;
        uint block;
        uint wantedPrice; // PRECISION
        uint slippageP; // PRECISION (%)
        uint spreadReductionP;
        uint tokenId;
    }

    struct PendingLimitOrder {
        address limitHolder;
        address trader;
        uint pairIndex;
        uint index;
        LimitOrder orderType;
    }

    // Trades mappings
    mapping(address => mapping(uint => mapping(uint => Trade)))
        public openTrades;
    mapping(address => mapping(uint => mapping(uint => bool)))
        public tempTradeStatus;
    mapping(address => mapping(uint => mapping(uint => uint256)))
        public openTimestamp;
    mapping(address => mapping(uint => mapping(uint => int256)))
        public accPerOiOpen;
    mapping(address => mapping(uint => mapping(uint => TradeInfo)))
        public openTradesInfo;
    mapping(address => mapping(uint => uint)) public openTradesCount;
    mapping(uint => PendingLimitOrder) public reqID_pendingLimitOrder;

    // Limit orders mappings
    mapping(address => mapping(uint => mapping(uint => uint)))
        public openLimitOrderIds;
    mapping(address => mapping(uint => uint)) public openLimitOrdersCount;
    OpenLimitOrder[] public openLimitOrders;

    // Pending orders mappings
    mapping(uint => PendingMarketOrder) public reqID_pendingMarketOrder;
    mapping(address => EnumerableSet.UintSet) private pendingOrderIds;
    mapping(address => mapping(uint => uint)) public pendingMarketOpenCount;
    mapping(address => mapping(uint => uint)) public pendingMarketCloseCount;

    // List of open trades & limit orders
    mapping(uint => address[]) public pairTraders;
    mapping(address => mapping(uint => uint)) public pairTradersId;

    // Current and max open interests for each pair
    mapping(uint => uint[5]) public openInterestUSDT; // usdtDecimals [long,short,max OI,max netOI, min netOI]
    

    // Restrictions & Timelocks
    mapping(uint => uint) public tradesPerBlock;

    // List of allowed contracts => can update storage + mint/burn tokens
    mapping(address => bool) public isTradingContract;

    // Events
    event SupportedTokenAdded(address a);
    event TradingContractAdded(address a);
    event TradingContractRemoved(address a);
    event AddressUpdated(string name, address a);
    event NumberUpdated(string name, uint value);
    event NumberUpdatedPair(string name, uint pairIndex, uint value);
    event SpreadReductionsUpdated(uint[5]);

    function initialize(
        address _USDT
        ) public initializer {
        gov = msg.sender;
        maxTradesPerPair = 3;
        maxPendingMarketOrders = 5;
        spreadReductionsP = [15, 20, 25, 30, 35]; // %
        PRECISION = 1e10;
        require(address(_USDT) != address(0), "ADDRESS_0");
        USDT = _USDT;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == gov, "Not gov");
        _;
    }
    modifier onlyTrading() {
        require(isTradingContract[msg.sender], "Not allowed");
        _;
    }

    // Set addresses
    function setPendingGovFund(address _gov) external onlyGov {
        require(_gov != address(0), "ADDRESS_0");
        pendingGov = _gov;
    }

    function confirmGovFund() external onlyGov {
        gov = pendingGov;
        emit AddressUpdated("govFund", gov);
    }

    // Trading + callbacks contracts
    function addTradingContract(address _trading) external onlyGov {
        require(_trading != address(0),"ADDRESS_0");
        isTradingContract[_trading] = true;
        emit TradingContractAdded(_trading);
    }

    function removeTradingContract(address _trading) external onlyGov {
        require(_trading != address(0),"ADDRESS_0");
        require(isTradingContract[_trading],"Not a trading contract");
        isTradingContract[_trading] = false;
        emit TradingContractRemoved(_trading);
    }

    function setPriceAggregator(address _aggregator) external onlyGov {
        require(_aggregator != address(0),"ADDRESS_0");
        priceAggregator = AggregatorInterface(_aggregator);
        emit AddressUpdated("priceAggregator", _aggregator);
    }

    function setPairInfos(PairInfoInterface _pairInfos) external onlyGov {
        require(address(_pairInfos) != address(0),"ADDRESS_0");
        pairInfos = _pairInfos;
        emit AddressUpdated("_pairInfos", address(_pairInfos));
    }

    function setPool(address _pool) external onlyGov {
        require(_pool != address(0),"ADDRESS_0");
        pool = PoolInterface(_pool);
        IERC20Upgradeable(USDT).approve(address(pool), type(uint256).max);
        emit AddressUpdated("pool", _pool);
    }

    function setVault(address _vault) external onlyGov {
        require(_vault != address(0),"ADDRESS_0");
        vault = _vault;
        emit AddressUpdated("vault", _vault);
    }

    function setTrading(address _trading) external onlyGov {
        require(_trading != address(0),"ADDRESS_0");
        trading = _trading;
        emit AddressUpdated("trading", _trading);
    }

    function setCallbacks(address _callbacks) external onlyGov {
        require(_callbacks != address(0),"ADDRESS_0");
        callbacks = _callbacks;
        emit AddressUpdated("callbacks", _callbacks);
    }

    function setMaxTradesPerPair(uint _maxTradesPerPair) external onlyGov {
        require(_maxTradesPerPair > 0,"MUST_ABOVE_0");
        maxTradesPerPair = _maxTradesPerPair;
        emit NumberUpdated("maxTradesPerPair", _maxTradesPerPair);
    }

    function setMaxPendingMarketOrders(
        uint _maxPendingMarketOrders
    ) external onlyGov {
        require(_maxPendingMarketOrders > 0,"MAX_PENDING_MARKET_ORDERS");
        maxPendingMarketOrders = _maxPendingMarketOrders;
        emit NumberUpdated("maxPendingMarketOrders", _maxPendingMarketOrders);
    }

    function setSpreadReductionsP(uint[5] calldata _r) external onlyGov {
        require(
            _r[0] > 0 &&
                _r[1] > _r[0] &&
                _r[2] > _r[1] &&
                _r[3] > _r[2] &&
                _r[4] > _r[3]
        ,"WRONG_SPREAD");
        spreadReductionsP = _r;
        emit SpreadReductionsUpdated(_r);
    }

    function setMaxOpenInterestUSDT(
        uint _pairIndex,
        uint _newMaxOpenInterest,
        uint _newMaxNetOpenInterest,
        uint _newMinNetOpenInterest
    ) external onlyGov {
        // Can set max open interest to 0 to pause trading on this pair only
        openInterestUSDT[_pairIndex][2] = _newMaxOpenInterest;
        openInterestUSDT[_pairIndex][3] = _newMaxNetOpenInterest;
        openInterestUSDT[_pairIndex][4] = _newMinNetOpenInterest;
        emit NumberUpdatedPair(
            "maxOpenInterestUSDT",
            _pairIndex,
            _newMaxOpenInterest
        );
    }

    function storePendingLimitOrder(
        PendingLimitOrder memory _limitOrder,
        uint _orderId
    ) external onlyTrading {
        reqID_pendingLimitOrder[_orderId] = _limitOrder;
        keeperForOrder[_orderId] = _limitOrder.limitHolder;
    }

    function unregisterPendingLimitOrder(uint _order) external onlyTrading {
        delete reqID_pendingLimitOrder[_order];
        keeperForOrder[_order] = address(0);
    }

    // Manage stored trades
    function storeTrade(
        Trade memory _trade,
        TradeInfo memory _tradeInfo
    ) external onlyTrading {
        require(_trade.index == firstEmptyTradeIndex(_trade.trader, _trade.pairIndex), "Wrong index");
        openTrades[_trade.trader][_trade.pairIndex][_trade.index] = _trade;
        openTimestamp[_trade.trader][_trade.pairIndex][_trade.index] = block.timestamp;
        if (_trade.buy) {
            accPerOiOpen[_trade.trader][_trade.pairIndex][_trade.index] = pairInfos.getAccFundingFeesLong(_trade.pairIndex);
        } else {
            accPerOiOpen[_trade.trader][_trade.pairIndex][_trade.index] = pairInfos.getAccFundingFeesShort(_trade.pairIndex);
        }
        openTradesCount[_trade.trader][_trade.pairIndex]++;
        tradesPerBlock[block.number]++;

        if (openTradesCount[_trade.trader][_trade.pairIndex] == 1) {
            pairTradersId[_trade.trader][_trade.pairIndex] = pairTraders[
                _trade.pairIndex
            ].length;
            pairTraders[_trade.pairIndex].push(_trade.trader);
        }

        _tradeInfo.beingMarketClosed = false;
        openTradesInfo[_trade.trader][_trade.pairIndex][
            _trade.index
        ] = _tradeInfo;

        updateOpenInterestUSDT(
            _trade.pairIndex,
            _tradeInfo.openInterestUSDT,
            true,
            _trade.buy
        );

        //Pre registering value to false to get a true at close
        tempTradeStatus[_trade.trader][_trade.pairIndex][_trade.index] = false;
    }

    function unregisterTrade(
        address trader,
        uint pairIndex,
        uint index
    ) external onlyTrading {
        Trade storage t = openTrades[trader][pairIndex][index];
        TradeInfo storage i = openTradesInfo[trader][pairIndex][index];
        if (t.leverage == 0) {
            return;
        }

        updateOpenInterestUSDT(pairIndex, i.openInterestUSDT, false, t.buy);

        if (openTradesCount[trader][pairIndex] == 1) {
            uint _pairTradersId = pairTradersId[trader][pairIndex];
            address[] storage p = pairTraders[pairIndex];

            p[_pairTradersId] = p[p.length - 1];
            pairTradersId[p[_pairTradersId]][pairIndex] = _pairTradersId;

            delete pairTradersId[trader][pairIndex];
            p.pop();
        }
        uint256 openTime = openTimestamp[trader][pairIndex][index];
        delete openTrades[trader][pairIndex][index];
        delete openTimestamp[trader][pairIndex][index];
        delete openTradesInfo[trader][pairIndex][index];
        delete accPerOiOpen[t.trader][t.pairIndex][t.index];
        tempTradeStatus[trader][pairIndex][index] = true;

        openTradesCount[trader][pairIndex]--;
        tradesPerBlock[block.number]++;
    }

    // Manage pending market orders
    function storePendingMarketOrder(
        PendingMarketOrder memory _order,
        uint _id,
        bool _open
    ) external onlyTrading {
        pendingOrderIds[_order.trade.trader].add(_id);
        reqID_pendingMarketOrder[_id] = _order;
        reqID_pendingMarketOrder[_id].block = block.number;

        if (_open) {
            pendingMarketOpenCount[_order.trade.trader][
                _order.trade.pairIndex
            ]++;
        } else {
            pendingMarketCloseCount[_order.trade.trader][
                _order.trade.pairIndex
            ]++;
            openTradesInfo[_order.trade.trader][_order.trade.pairIndex][
                _order.trade.index
            ].beingMarketClosed = true;
        }
    }

    function unregisterPendingMarketOrder(
        uint _id,
        bool _open
    ) external onlyTrading {
        PendingMarketOrder memory _order = reqID_pendingMarketOrder[_id];
        bool removed = pendingOrderIds[_order.trade.trader].remove(_id);

        if (removed) {
            if (_open) {
                pendingMarketOpenCount[_order.trade.trader][
                    _order.trade.pairIndex
                ]--;
            } else {
                pendingMarketCloseCount[_order.trade.trader][
                    _order.trade.pairIndex
                ]--;
                openTradesInfo[_order.trade.trader][_order.trade.pairIndex][
                    _order.trade.index
                ].beingMarketClosed = false;
            }
            delete reqID_pendingMarketOrder[_id];
        }
    }

    // Manage open interest
    function updateOpenInterestUSDT(
        uint _pairIndex,
        uint _leveragedPosUSDT,
        bool _open,
        bool _long
    ) private {
        uint index = _long ? 0 : 1;
        uint[5] storage o = openInterestUSDT[_pairIndex];
        o[index] = _open
            ? o[index] + _leveragedPosUSDT
            : o[index] - _leveragedPosUSDT;
    }

    // Manage open limit orders
    function storeOpenLimitOrder(OpenLimitOrder memory o) external onlyTrading {
        o.index = firstEmptyOpenLimitIndex(o.trader, o.pairIndex);
        o.block = block.number;
        openLimitOrders.push(o);
        openLimitOrderIds[o.trader][o.pairIndex][o.index] =
            openLimitOrders.length -
            1;
        openLimitOrdersCount[o.trader][o.pairIndex]++;
    }

    function updateOpenLimitOrder(
        OpenLimitOrder calldata _o
    ) external onlyTrading {
        if (!hasOpenLimitOrder(_o.trader, _o.pairIndex, _o.index)) {
            return;
        }
        OpenLimitOrder storage o = openLimitOrders[
            openLimitOrderIds[_o.trader][_o.pairIndex][_o.index]
        ];
        o.positionSize = _o.positionSize;
        o.buy = _o.buy;
        o.leverage = _o.leverage;
        o.tp = _o.tp;
        o.sl = _o.sl;
        o.minPrice = _o.minPrice;
        o.maxPrice = _o.maxPrice;
        o.block = block.number;
    }

    function unregisterOpenLimitOrder(
        address _trader,
        uint _pairIndex,
        uint _index
    ) external onlyTrading {
        if (!hasOpenLimitOrder(_trader, _pairIndex, _index)) {
            return;
        }

        // Copy last order to deleted order => update id of this limit order
        uint id = openLimitOrderIds[_trader][_pairIndex][_index];
        openLimitOrders[id] = openLimitOrders[openLimitOrders.length - 1];
        openLimitOrderIds[openLimitOrders[id].trader][
            openLimitOrders[id].pairIndex
        ][openLimitOrders[id].index] = id;

        // Remove
        delete openLimitOrderIds[_trader][_pairIndex][_index];
        openLimitOrders.pop();

        openLimitOrdersCount[_trader][_pairIndex]--;
    }

    // Manage open trade
    function updateSl(
        address _trader,
        uint _pairIndex,
        uint _index,
        uint _newSl
    ) external onlyTrading {
        Trade storage t = openTrades[_trader][_pairIndex][_index];
        TradeInfo storage i = openTradesInfo[_trader][_pairIndex][_index];
        if (t.leverage == 0) {
            return;
        }
        t.sl = _newSl;
        i.slLastUpdated = block.number;
    }

    function updateTp(
        address _trader,
        uint _pairIndex,
        uint _index,
        uint _newTp
    ) external onlyTrading {
        Trade storage t = openTrades[_trader][_pairIndex][_index];
        TradeInfo storage i = openTradesInfo[_trader][_pairIndex][_index];
        if (t.leverage == 0) {
            return;
        }
        t.tp = _newTp;
        i.tpLastUpdated = block.number;
    }

    function updateTrade(Trade memory _t) external onlyTrading {
        // useful when partial adding/closing
        Trade storage t = openTrades[_t.trader][_t.pairIndex][_t.index];
        if (t.leverage == 0) {
            return;
        }
        t.initialPosToken = _t.initialPosToken;
        t.positionSizeUSDT = _t.positionSizeUSDT;
        t.openPrice = _t.openPrice;
        t.leverage = _t.leverage;
    }

    // Manage rewards
    function distributeLpRewards(uint _amount) external onlyTrading {
        pool.increaseAccTokens(_amount);
    }

    function transferUSDT(
        address _from,
        address _to,
        uint _amount
    ) external onlyTrading {
        if (_from == address(this)) {
            IERC20Upgradeable(USDT).safeTransfer(_to, _amount);
            
        } else {
            IERC20Upgradeable(USDT).safeTransferFrom(_from, _to, _amount);
        }
    }

    function getNetOI(uint256 _pairIndex, bool _long) external view returns (uint256) {
        int256 longOI = int256(openInterestUSDT[_pairIndex][0]);
        int256 shortOI = int256(openInterestUSDT[_pairIndex][1]);

        int256 netOI;
        if (_long) {
            netOI = longOI - shortOI;
        } else {
            netOI = shortOI - longOI;
        }
        
        return abs(netOI);
    }

    function abs(int256 x) private pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    // View utils functions
    function firstEmptyTradeIndex(
        address trader,
        uint pairIndex
    ) public view returns (uint index) {
        bool allOccupied = true;

        for (uint i = 0; i < maxTradesPerPair; i++) {
            if (openTrades[trader][pairIndex][i].leverage == 0) {
                index = i;
                allOccupied = false;
                break;
            }
        }

        require(!allOccupied, "All open limit slots are full");
        return index;
    }

    function firstEmptyOpenLimitIndex(
        address trader,
        uint pairIndex
    ) public view returns (uint index) {
        bool allOccupied = true;
        for (uint i = 0; i < maxTradesPerPair; i++) {
            if (!hasOpenLimitOrder(trader, pairIndex, i)) {
                index = i;
                allOccupied = false;
                break;
            }
        }
        
        require(!allOccupied, "All open limit slots are full");
        return index;
    }

    function hasOpenLimitOrder(
        address trader,
        uint pairIndex,
        uint index
    ) public view returns (bool) {
        if (openLimitOrders.length == 0) {
            return false;
        }
        OpenLimitOrder storage o = openLimitOrders[
            openLimitOrderIds[trader][pairIndex][index]
        ];
        return
            o.trader == trader && o.pairIndex == pairIndex && o.index == index;
    }

    function pairTradersArray(
        uint _pairIndex
    ) external view returns (address[] memory) {
        return pairTraders[_pairIndex];
    }


    function getPendingOrderIds(
        address _trader
    ) external view returns (uint[] memory) {
        EnumerableSet.UintSet storage idsSet = pendingOrderIds[_trader];
        uint256 length = idsSet.length();
        uint[] memory idsArray = new uint[](length);

        for (uint256 i = 0; i < length; i++) {
            idsArray[i] = idsSet.at(i);
        }

        return idsArray;
    }

    function pendingOrderIdsCount(
        address _trader
    ) external view returns (uint) {
        return pendingOrderIds[_trader].length();
    }

    function getOpenLimitOrder(
        address _trader,
        uint _pairIndex,
        uint _index
    ) external view returns (OpenLimitOrder memory) {
        require(hasOpenLimitOrder(_trader, _pairIndex, _index),"MUST_HAVE_OPEN_LIMIT");
        return openLimitOrders[openLimitOrderIds[_trader][_pairIndex][_index]];
    }

    function getOpenLimitOrders()
        external
        view
        returns (OpenLimitOrder[] memory)
    {
        return openLimitOrders;
    }

    function getSpreadReductionsArray() external view returns (uint[5] memory) {
        return spreadReductionsP;
    }
}

