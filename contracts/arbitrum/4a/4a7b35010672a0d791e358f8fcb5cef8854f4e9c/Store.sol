// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AggregatorV3Interface.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";

contract DataStore {
    
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DIVIDER = 10000;
    address public gov;
    address public currency;
    address public GML;

    address public trade;
    address public pool;

    
    uint256 public poolFeeShare = 5000; // in bps
    uint256 public keeperFeeShare = 1000; // in bps
    uint256 public poolWithdrawalFee = 10; // in bps
    uint256 public minimumMarginLevel = 2000; // 20% in bps, at which account is liquidated

    address[] public currencies;
    mapping (address => bool) supported;
    mapping (uint256 => bool) isActive;

        // Funding
	uint256 public constant fundingInterval = 1 hours; // In seconds.

	mapping(uint256 => int256) private fundingTrackers; // market => funding tracker (long) (short is opposite) // in UNIT * bps
	mapping(uint256 => uint256) private fundingLastUpdated; // market => last time fundingTracker was updated. In seconds.

    struct MarketData { 
        uint256 marketType; // 1 = crypto , 2 = forex  
        string symbol;
        address feed;
        uint256 maxLeverage;
        uint256 maxOI;
        uint256 fee; // in bps
        uint256 fundingFactor; // Yearly funding rate if OI is completely skewed to one side. In bps.
        uint256 minSize;
        uint256 minSettlementTime; // time before keepers can execute order (price finality) if chainlink price didn't change   
    }

    struct OrderData {
      uint256 orderId;
        address user;
        address currency;
        string market;
        uint256 marketId;
        uint256 price;
        bool isLong;
        uint256 leverage;
        uint8 orderType; // 0 = market, 1 = limit, 2 = stop
        uint256 margin;
        uint256 timestamp;
        uint256 takeProfit;
        uint256 stopLoss;
        bool isActive;
    }

    struct PositionData {
        address user;
        string market;
        uint256 marketId;
        bool isLong;
        uint256 size;
		uint256 margin;
		int256 fundingTracker;
		uint256 price;
		uint256 timestamp;
    }

    mapping (uint256 => PositionData) public userPositonItem;
    EnumerableSet.UintSet private positionKeys; // [position keys..]
    mapping(address => EnumerableSet.UintSet) private userPositionIds;

    mapping(uint256 => OrderData) public orders;
    mapping (address => EnumerableSet.UintSet) private userOrderIds;
    EnumerableSet.UintSet private orderIdsSet; 

        
    mapping(uint256 => uint256) public openIntrestLong;
    mapping(uint256 => uint256) public openIntrestShort;

    uint256 public markertPairId;
    mapping (uint256 => bool) public isMarketAdded;


    uint256[] public marketList; // "ETH-USD", "BTC-USD", etc
    mapping(uint256 => MarketData) public marketItems;

    mapping(address => uint256) private balances; // user => amount
    mapping(address => uint256) private lockedMargins; // user => amount

    uint256 public orderId;

    constructor (){
        gov = msg.sender;
    }

   function transferIn(address user, uint256 amount) external onlyContract {
		IERC20(currency).safeTransferFrom(user, address(this), amount);
	}

    function transferOut(address user, uint256 amount) external onlyContract {
        IERC20(currency).safeTransfer(user, amount);
	}

    function linkData (address _trading) external onlyGov{
        trade = _trading;
        // pool = _pool;
    }

    function addMarket(MarketData memory marketInfo) external onlyGov {
        uint256 id =  markertPairId++;
        require(isMarketAdded[id] == false,"id has been used");
        marketItems[id] = marketInfo;
        marketList.push(id);
        isMarketAdded[id] = true;
    }

    function updateMarket(uint256 martketId ,MarketData memory marketInfo) external onlyGov {
        require(isMarketAdded[martketId] == false,"id has been used");
        marketItems[martketId] = marketInfo;
    }

    function setPoolShare(uint256 bps) external onlyGov {
        poolFeeShare = bps;
    }

    function incrementOpenInterest ( uint256 marketId, uint256 amount, bool isLong ) external onlyContract {
        if (isLong){
            openIntrestLong[marketId] += amount;
        }else{
            openIntrestShort[marketId] += amount;
        }
    }

    function decreaseOpenIntrest ( uint256 marketId, uint256 amount, bool isLong ) external onlyContract {
        if (isLong){
            if (amount > openIntrestLong[marketId]){
                openIntrestLong[marketId] = 0;
            }else{
                openIntrestLong[marketId] -= amount;
            }
        }else{
            if (amount > openIntrestShort[marketId]) {
                openIntrestShort[marketId] = 0;
            }else {
                openIntrestShort[marketId] = 0;
            }
        }
    }

    

    function getOpenIntrestLong (uint256 marketId) external view returns(uint256) {
        return openIntrestLong[marketId];

    }

    function getOpenIntrestShort (uint256 marketId) external view returns(uint256) {
        return openIntrestShort[marketId];
    }

    function getMarketPairsData () external view returns(uint256[] memory){
        return marketList;
    }

    function getMarket (uint256 id) external view returns (MarketData memory _marketData){
        return marketItems[id];
    }

    function getOrder (uint256 id) external view returns (OrderData memory _orders){
        return orders[id];
    }
    

    

    function getOrders() external view returns (OrderData[] memory _orders) {
        uint256 length = orderIdsSet.length();
        _orders = new OrderData[](length);
        for (uint256 i =0; i < length; i++){
            _orders[i] = orders[orderIdsSet.at(i)];
        }
        return _orders;
    }

    
    function activateLimitOrders(uint256 id) external onlyContract {
        OrderData storage order = orders[id];
        require(order.price > 0,"!price");
        require(order.orderType == 1,"!limit");
        order.isActive = true;
    }

    function getUserOrders(address user) external view returns (OrderData[] memory _userOrders){
        uint256 length = userOrderIds[user].length();
        _userOrders = new OrderData[](length);

        for (uint256 i = 0; i <length; i++){
            _userOrders[i] = orders[userOrderIds[user].at(i)];
        }
        return _userOrders;
    }

    function getUserPositions (address user) 
        external view returns (PositionData[] memory _positions){

        uint256 length = userPositionIds[user].length();
        _positions = new PositionData[](length);
        for (uint256 i =0; i< length; i++){
            _positions[i] = userPositonItem[userPositionIds[user].at(i)];
        }
        return _positions;
    }

    function addOrder (OrderData memory order) external onlyContract returns(uint256){
        uint256 nextOrderId = ++orderId;
        order.orderId = nextOrderId;
        userOrderIds[order.user].add(nextOrderId);
        orders[nextOrderId] = order;
        orderIdsSet.add(nextOrderId);
        return nextOrderId;
    }

    function removeOrder (uint256 _orderId) external onlyContract {
        OrderData memory order = orders[_orderId];
        userOrderIds[order.user].remove(_orderId);
        orderIdsSet.remove(_orderId);
        delete orders[_orderId];
    }

    function addMargin (uint256 id, uint256 amount) external onlyContract{
         OrderData storage order = orders[id];
        require(order.price > 0,"!price");
        require(amount > 0, "!amount");
        uint256 newMargin = order.margin + amount;
        uint256 newLeverage = (order.leverage * order.margin) / newMargin;
        order.margin = newMargin;
        order.leverage = newLeverage;
    }
 
    function addOrUpdateUserPosition (address user, uint256 nextPositionId) external onlyContract {
        userPositionIds[user].add(nextPositionId);
        positionKeys.add(nextPositionId);
    }

	function isSupportedCurrency(address token) external view returns(bool) {
        require( token != address(0),"!currency" );
        require(supported[token] != false,"!supported");
		return supported[token];
	}

	function currenciesLength() external view returns(uint256) {
		return currencies.length;
	}

	function setCurrencies(address token) external onlyGov {
        require( token != address(0),"!currency" );
        supported[token] = true;
        currencies.push(token);
	}


    function removeUserPosition (address user, uint256 id) external onlyContract{
        userPositionIds[user].remove(id);
    }

    
	function getFundingFactor (uint256 marketId) external view returns(uint256) {
        return marketItems[marketId].fundingFactor;
	}

    function getFundingLastUpdated(uint256 marketId) external view returns(uint256) {
		return fundingLastUpdated[marketId];
	}
    
    function getFundingTracker(uint256 marketId) external view returns(int256) {
		return fundingTrackers[marketId];
	}

    function setFundingLastUpdated(uint256 marketId, uint256 timestamp) external onlyContract {
		fundingLastUpdated[marketId] = timestamp;
	}

	function updateFundingTracker(uint256 marketId, int256 fundingIncrement) external onlyContract {
		fundingTrackers[marketId] += fundingIncrement;
	}


    // Mods
        modifier onlyContract() {
        require(msg.sender == trade || msg.sender == pool || msg.sender == gov, '!contract');
        _;
    }

    modifier onlyGov() {
        require(msg.sender == gov, '!gov');
        _;
    }



}
