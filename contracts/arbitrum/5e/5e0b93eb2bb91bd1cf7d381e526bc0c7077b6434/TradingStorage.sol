// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ITradingStorage.sol";


contract TradingStorage {

    uint256 public constant PRECISION = 1e10;

    enum LimitOrder { TP, SL, LIQ, OPEN }

    struct Trade{
        address trader;
        uint256 pairIndex;
        uint256 index;
        uint256 positionSizeStable;     
        uint256 openPrice;            
        bool buy;
        uint256 leverage;
        uint256 tp;                  
        uint256 sl;                   
    }

    struct TradeInfo{
        uint256 tokenId;      
        uint256 openInterestStable;      
        uint256 tpLastUpdated;
        uint256 slLastUpdated;
        bool beingMarketClosed;
    }

    struct OpenLimitOrder{
        address trader;
        uint256 pairIndex;
        uint256 index;
        uint256 positionSize;          
        bool buy;
        uint256 leverage;
        uint256 tp;                   
        uint256 sl;                
        uint256 minPrice;             
        uint256 maxPrice;            
        uint256 block;
        uint256 tokenId;               // index in supportedTokens
    }

    struct PendingMarketOrder{
        Trade trade;
        uint256 block;
        uint256 wantedPrice;       
        uint256 slippageP;          
        uint256 tokenId;               // index in supportedTokens
    }

    struct PendingBotOrder{
        address trader;
        uint256 pairIndex;
        uint256 index;
        LimitOrder orderType;
    }

    IAggregator01 public priceAggregator;
    IWorkPool public workPool;
    TokenInterface public stable;
    TokenInterface public linkErc677;
    IOrderExecutionTokenManagement public orderTokenManagement;

    address public trading;
    address public callbacks;

    uint256 public maxTradesPerPair;
    uint256 public maxPendingMarketOrders;

    address public gov;
    address public dev;
    address public ref;

    uint256 public devFeesStable;    
    uint256 public govFeesStable;    
    uint256 public refFeesStable;   

    address[] public supportedTokens;

    // Trades mappings
    mapping(address => mapping(uint256 => mapping(uint256 => Trade))) public openTrades;
    mapping(address => mapping(uint256 => mapping(uint256 => TradeInfo))) public openTradesInfo;
    mapping(address => mapping(uint256 => uint256)) public openTradesCount;

    // Limit orders mappings
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public openLimitOrderIds;
    mapping(address => mapping(uint256 => uint256)) public openLimitOrdersCount;
    OpenLimitOrder[] public openLimitOrders;

    // Pending orders mappings
    mapping(uint256 => PendingMarketOrder) public reqID_pendingMarketOrder;
    mapping(uint256 => PendingBotOrder) public reqID_pendingBotOrder;
    mapping(address => uint256[]) public pendingOrderIds;
    mapping(address => mapping(uint256 => uint256)) public pendingMarketOpenCount;
    mapping(address => mapping(uint256 => uint256)) public pendingMarketCloseCount;

    // List of open trades & limit orders
    mapping(uint256 => address[]) public pairTraders;
    mapping(address => mapping(uint256 => uint256)) public pairTradersId;

    // Current and max open interests for each pair
    mapping(uint256 => uint256[3]) public openInterestStable; // [long,short,max]

    mapping(address => bool) public isTradingContract;

    event SupportedTokenAdded(address a);
    event TradingContractAdded(address a);
    event TradingContractRemoved(address a);
    event AddressUpdated(string name, address a);
    event NumberUpdated(string name,uint256 value);
    event NumberUpdatedPair(string name,uint256 pairIndex,uint256 value);
    event SpreadReductionsUpdated(uint256[5]);

    error StorageTWrongParameters();
    error StorageTInvalidGovAddress(address account);
    error StorageTInvalidTradingContract(address account);
    error StorageTInvalidAddress(address account);
    error StorageTNoLimitOrder();

    modifier onlyGov() { 
        if (msg.sender != gov) {
            revert StorageTInvalidGovAddress(msg.sender);
        }
         _; 
    }

    modifier onlyTrading() { 
        if (!isTradingContract[msg.sender]) {
            revert StorageTInvalidTradingContract(msg.sender);
        }
        _; 
    }

    constructor(
        TokenInterface _stable,
        TokenInterface _linkErc677,
        address _gov,
        address _dev,
        address _ref
    ) {
        if (address(_stable) == address(0) || 
            address(_linkErc677) == address(0) || 
            _gov == address(0) ||
            _dev == address(0) || 
            _ref == address(0)
        ) 
        {
            revert StorageTWrongParameters();
        }

        stable = _stable;
        linkErc677 = _linkErc677;

        gov = _gov;
        dev = _dev;
        ref = _ref;

        maxTradesPerPair = 3;
        maxPendingMarketOrders = 5;
    }


    function setGov(address _gov) external onlyGov{
        if (_gov == address(0)) revert StorageTInvalidAddress(address(0));
        gov = _gov;
        emit AddressUpdated("gov", _gov);
    }
    function setDev(address _dev) external onlyGov{
        if (_dev == address(0)) revert StorageTInvalidAddress(address(0));
        dev = _dev;
        emit AddressUpdated("dev", _dev);
    }
    function setRef(address _ref) external onlyGov{
        if (_ref == address(0)) revert StorageTInvalidAddress(address(0));
        ref = _ref;
        emit AddressUpdated("ref", _ref);
    }

    function addTradingContract(address _trading) external onlyGov{
        if (_trading == address(0)) revert StorageTInvalidAddress(address(0));
        isTradingContract[_trading] = true;
        emit TradingContractAdded(_trading);
    }
    function removeTradingContract(address _trading) external onlyGov{
        if (_trading == address(0)) revert StorageTInvalidAddress(address(0));
        isTradingContract[_trading] = false;
        emit TradingContractRemoved(_trading);
    }
    function addSupportedToken(address _token) external onlyGov{
        if (_token == address(0)) revert StorageTInvalidAddress(address(0));
        supportedTokens.push(_token);
        emit SupportedTokenAdded(_token);
    }
    function setPriceAggregator(address _aggregator) external onlyGov{
        if (_aggregator == address(0)) revert StorageTInvalidAddress(address(0));
        priceAggregator = IAggregator01(_aggregator);
        emit AddressUpdated("priceAggregator", _aggregator);
    }
    function setOrderTokenManagement(address _orderTokenManagement) external onlyGov{
        if (_orderTokenManagement == address(0)) revert StorageTInvalidAddress(address(0));
        orderTokenManagement = IOrderExecutionTokenManagement(_orderTokenManagement);
        emit AddressUpdated("OrderTokenManagement", _orderTokenManagement);
    }
    function setWorkPool(address _workPool) external onlyGov{
        if (_workPool == address(0)) revert StorageTInvalidAddress(address(0));
        workPool = IWorkPool(_workPool);
        emit AddressUpdated("workPool", _workPool);
    }
    function setTrading(address _trading) external onlyGov{
        if (_trading == address(0)) revert StorageTInvalidAddress(address(0));
        trading = _trading;
        emit AddressUpdated("trading", _trading);
    }
    function setCallbacks(address _callbacks) external onlyGov{
        if (_callbacks == address(0)) revert StorageTInvalidAddress(address(0));
        callbacks = _callbacks;
        emit AddressUpdated("callbacks", _callbacks);
    }

    function setMaxTradesPerPair(uint256 _maxTradesPerPair) external onlyGov{
        if (_maxTradesPerPair == 0) revert StorageTWrongParameters();
        maxTradesPerPair = _maxTradesPerPair;
        emit NumberUpdated("maxTradesPerPair", _maxTradesPerPair);
    }
    function setMaxPendingMarketOrders(uint256 _maxPendingMarketOrders) external onlyGov{
        if (_maxPendingMarketOrders == 0) revert StorageTWrongParameters();
        maxPendingMarketOrders = _maxPendingMarketOrders;
        emit NumberUpdated("maxPendingMarketOrders", _maxPendingMarketOrders);
    }
    function setMaxOpenInterestStable(uint256 _pairIndex, uint256 _newMaxOpenInterest) external onlyGov{
        openInterestStable[_pairIndex][2] = _newMaxOpenInterest;
        emit NumberUpdatedPair("maxOpenInterestStable", _pairIndex, _newMaxOpenInterest);
    }

    function storeTrade(Trade memory _trade, TradeInfo memory _tradeInfo) external onlyTrading{
        _trade.index = firstEmptyTradeIndex(_trade.trader, _trade.pairIndex);
        openTrades[_trade.trader][_trade.pairIndex][_trade.index] = _trade;

        openTradesCount[_trade.trader][_trade.pairIndex]++;

        if(openTradesCount[_trade.trader][_trade.pairIndex] == 1){
            pairTradersId[_trade.trader][_trade.pairIndex] = pairTraders[_trade.pairIndex].length;
            pairTraders[_trade.pairIndex].push(_trade.trader); 
        }

        _tradeInfo.beingMarketClosed = false;
        openTradesInfo[_trade.trader][_trade.pairIndex][_trade.index] = _tradeInfo;

        updateOpenInterestStable(_trade.pairIndex, _tradeInfo.openInterestStable, true, _trade.buy);
    }

    function unregisterTrade(address trader, uint256 pairIndex, uint256 index) external onlyTrading{
        Trade storage t = openTrades[trader][pairIndex][index];
        TradeInfo storage i = openTradesInfo[trader][pairIndex][index];
        if(t.leverage == 0){ return; }

        updateOpenInterestStable(pairIndex, i.openInterestStable, false, t.buy);

        if(openTradesCount[trader][pairIndex] == 1){
            uint256 _pairTradersId = pairTradersId[trader][pairIndex];
            address[] storage p = pairTraders[pairIndex];

            p[_pairTradersId] = p[p.length-1];
            pairTradersId[p[_pairTradersId]][pairIndex] = _pairTradersId;
            
            delete pairTradersId[trader][pairIndex];
            p.pop();
        }

        delete openTrades[trader][pairIndex][index];
        delete openTradesInfo[trader][pairIndex][index];

        openTradesCount[trader][pairIndex]--;
    }

    // Manage pending market orders
    function storePendingMarketOrder(PendingMarketOrder memory _order, uint256 _id, bool _open) external onlyTrading{
        pendingOrderIds[_order.trade.trader].push(_id);

        reqID_pendingMarketOrder[_id] = _order;
        reqID_pendingMarketOrder[_id].block = block.number;
        
        if(_open){
            pendingMarketOpenCount[_order.trade.trader][_order.trade.pairIndex]++;
        }else{
            pendingMarketCloseCount[_order.trade.trader][_order.trade.pairIndex]++;
            openTradesInfo[_order.trade.trader][_order.trade.pairIndex][_order.trade.index].beingMarketClosed = true;
        }
    }

    function unregisterPendingMarketOrder(uint256 _id, bool _open) external onlyTrading{
        PendingMarketOrder memory _order = reqID_pendingMarketOrder[_id];
        uint256[] storage orderIds = pendingOrderIds[_order.trade.trader];

        for(uint256 i = 0; i < orderIds.length; i++){
            if(orderIds[i] == _id){
                if(_open){ 
                    pendingMarketOpenCount[_order.trade.trader][_order.trade.pairIndex]--;
                }else{
                    pendingMarketCloseCount[_order.trade.trader][_order.trade.pairIndex]--;
                    openTradesInfo[_order.trade.trader][_order.trade.pairIndex][_order.trade.index].beingMarketClosed = false;
                }

                orderIds[i] = orderIds[orderIds.length-1];
                orderIds.pop();

                delete reqID_pendingMarketOrder[_id];
                return;
            }
        }
    }

    // Manage open limit orders
    function storeOpenLimitOrder(OpenLimitOrder memory o) external onlyTrading{
        o.index = firstEmptyOpenLimitIndex(o.trader, o.pairIndex);
        o.block = block.number;
        openLimitOrders.push(o);
        openLimitOrderIds[o.trader][o.pairIndex][o.index] = openLimitOrders.length-1;
        openLimitOrdersCount[o.trader][o.pairIndex]++;
    }

    function updateOpenLimitOrder(OpenLimitOrder calldata _o) external onlyTrading{
        if(!hasOpenLimitOrder(_o.trader, _o.pairIndex, _o.index)){ return; }
        OpenLimitOrder storage o = openLimitOrders[openLimitOrderIds[_o.trader][_o.pairIndex][_o.index]];
        o.positionSize = _o.positionSize;
        o.buy = _o.buy;
        o.leverage = _o.leverage;
        o.tp = _o.tp;
        o.sl = _o.sl;
        o.minPrice = _o.minPrice;
        o.maxPrice = _o.maxPrice;
        o.block = block.number;
    }

    function unregisterOpenLimitOrder(address _trader, uint256 _pairIndex, uint256 _index) external onlyTrading{
        if(!hasOpenLimitOrder(_trader, _pairIndex, _index)){ return; }

        // Copy last order to deleted order => update id of this limit order
        uint256 id = openLimitOrderIds[_trader][_pairIndex][_index];
        openLimitOrders[id] = openLimitOrders[openLimitOrders.length-1];
        openLimitOrderIds[openLimitOrders[id].trader][openLimitOrders[id].pairIndex][openLimitOrders[id].index] = id;

        delete openLimitOrderIds[_trader][_pairIndex][_index];
        openLimitOrders.pop();

        openLimitOrdersCount[_trader][_pairIndex]--;
    }

    // Manage Bot orders
    function storePendingBotOrder(PendingBotOrder memory _botOrder, uint256 _orderId) external onlyTrading{
        reqID_pendingBotOrder[_orderId] = _botOrder;
    }

    function unregisterPendingBotOrder(uint256 _order) external onlyTrading{
        delete reqID_pendingBotOrder[_order];
    }

    // Manage open trade
    function updateSl(address _trader, uint256 _pairIndex, uint256 _index, uint256 _newSl) external onlyTrading{
        Trade storage t = openTrades[_trader][_pairIndex][_index];
        TradeInfo storage i = openTradesInfo[_trader][_pairIndex][_index];
        if(t.leverage == 0){ return; }
        t.sl = _newSl;
        i.slLastUpdated = block.number;
    }

    function updateTp(address _trader, uint256 _pairIndex, uint256 _index, uint256 _newTp) external onlyTrading{
        Trade storage t = openTrades[_trader][_pairIndex][_index];
        TradeInfo storage i = openTradesInfo[_trader][_pairIndex][_index];
        if(t.leverage == 0){ return; }
        t.tp = _newTp;
        i.tpLastUpdated = block.number;
    }

    function updateTrade(Trade memory _t) external onlyTrading{ // useful when partial adding/closing
        Trade storage t = openTrades[_t.trader][_t.pairIndex][_t.index];
        if(t.leverage == 0){ return; }
        t.positionSizeStable = _t.positionSizeStable;
        t.openPrice = _t.openPrice;
        t.leverage = _t.leverage;
    }

    function handleDevGovRefFees(uint256 _pairIndex, uint256 _leveragedPositionSize, bool _isRef, bool _fullFee) external onlyTrading returns(uint256 fee){
        fee = _leveragedPositionSize * priceAggregator.openFeeP(_pairIndex) / PRECISION / 100;
        if(!_fullFee){ fee /= 2; }
    
        govFeesStable += fee;
        devFeesStable += fee;

        if (_isRef) {
            refFeesStable += fee;
            fee *= 3;
        } else {
            fee *= 2;
        }
    }

    function claimFees() external onlyGov{
        stable.transfer(gov, govFeesStable);
        stable.transfer(dev, devFeesStable);
        stable.transfer(ref, refFeesStable);

        devFeesStable = 0;
        govFeesStable = 0;
        refFeesStable = 0;
    }

    function transferStable(address _from, address _to, uint256 _amount) external onlyTrading{ 
        if(_from == address(this)){
            stable.transfer(_to, _amount); 
        }else{
            stable.transferFrom(_from, _to, _amount); 
        }
    }

    function pairTradersArray(uint256 _pairIndex) external view returns(address[] memory){ 
        return pairTraders[_pairIndex]; 
    }

    function getPendingOrderIds(address _trader) external view returns(uint256[] memory){ 
        return pendingOrderIds[_trader]; 
    }

    function pendingOrderIdsCount(address _trader) external view returns(uint256){ 
        return pendingOrderIds[_trader].length; 
    }

    function getOpenLimitOrder(
        address _trader, 
        uint256 _pairIndex,
        uint256 _index
    ) external view returns(OpenLimitOrder memory){ 
        if (!hasOpenLimitOrder(_trader, _pairIndex, _index)) {
            revert StorageTNoLimitOrder();
        }
        return openLimitOrders[openLimitOrderIds[_trader][_pairIndex][_index]]; 
    }

    function getOpenLimitOrders() external view returns(OpenLimitOrder[] memory){ 
        return openLimitOrders; 
    }

    function getSupportedTokens() external view returns(address[] memory){ 
        return supportedTokens; 
    }

    function firstEmptyTradeIndex(address trader, uint256 pairIndex) public view returns(uint256 index){
        for(uint256 i = 0; i < maxTradesPerPair; i++){
            if(openTrades[trader][pairIndex][i].leverage == 0){ index = i; break; }
        }
    }

    function firstEmptyOpenLimitIndex(address trader, uint256 pairIndex) public view returns(uint256 index){
        for(uint i = 0; i < maxTradesPerPair; i++){
            if(!hasOpenLimitOrder(trader, pairIndex, i)){ index = i; break; }
        }
    }

    function hasOpenLimitOrder(address trader, uint256 pairIndex, uint256 index) public view returns(bool){
        if(openLimitOrders.length == 0){ return false; }
        OpenLimitOrder storage o = openLimitOrders[openLimitOrderIds[trader][pairIndex][index]];
        return o.trader == trader && o.pairIndex == pairIndex && o.index == index;
    }

    function updateOpenInterestStable(uint256 _pairIndex, uint256 _leveragedPosStable, bool _open, bool _long) private{
        uint256 index = _long ? 0 : 1;
        uint256[3] storage o = openInterestStable[_pairIndex];
        o[index] = _open ? o[index] + _leveragedPosStable : o[index] - _leveragedPosStable;
    }
}

