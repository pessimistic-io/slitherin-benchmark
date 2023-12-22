// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./MarketDataStructure.sol";

contract MarketStorage {
    // amount decimal 1e20
    int256 public constant AMOUNT_PRECISION = 1e20;

    string public token;//indexToken，like `BTC_USD`,price key
    uint8 public marketType = 0;//contract type ,0:usd-m,1:coin-m,2:mix-m
    address public pool;//pool address
    address internal manager;//manager address
    address public marketLogic;//marketLogic address
    address internal fundingLogic;//fundingLogic address
    address internal marginAsset;//margin asset address
    MarketDataStructure.MarketConfig internal marketConfig;//marketConfig

    uint256 public positionID;//positionID
    uint256 public orderID;//orderID
    uint256 public triggerOrderID = type(uint128).max;  //trigger Order ID
    //taker => key => positionID
    mapping(address => mapping(MarketDataStructure.PositionKey => uint256)) internal takerPositionList;//key: short;long;cross
    //taker => orderID[]
    mapping(address => uint256[]) internal takerOrderList;
    //orderId => order
    mapping(uint256 => MarketDataStructure.Order) internal orders;
    //positionId => position
    mapping(uint256 => MarketDataStructure.Position) internal takerPositions;
    //taker => marginMode
    mapping(address => MarketDataStructure.PositionMode) public positionModes;//0 cross marginMode；1 Isolated marginMode
    //taker => orderType => orderNum, orderNum < maxOrderLimit
    mapping(address => mapping(MarketDataStructure.OrderType => uint256)) public takerOrderNum;
    //taker => direction => orderTotalValue,orderTotalValue < maxOrderValueLimit
    mapping(address => mapping(int8 => int256)) public takerOrderTotalValues;
    //cumulative funding rate,it`s last funding rate, fundingGrowthGlobalX96 be equivalent to frX96
    int256 public fundingGrowthGlobalX96;
    //last update funding rate timestamp
    uint256 public lastFrX96Ts;//lastFrX96Ts
    uint256 public lastExecutedOrderId;

    event Initialize(string indexToken, address _clearAnchor, address _pool, uint8 _marketType);
    event LogicAddressesModified(address _marketLogic, address _fundingLogic);
    event SetMarketConfig(MarketDataStructure.MarketConfig _marketConfig);
    event ExecuteOrderError(uint256 _orderId, uint256 _errCode);
    event ExecuteFeeInfo(uint256 id, bytes32 code, address taker, address inviter, address token, uint256 value, uint256 feeToInviter, uint256 feeToDiscount);
    event UpdateMargin(uint256 id, int256 deltaMargin);
    event SwitchPositionMode(address taker, MarketDataStructure.PositionMode mode);
    event DustPositionClosed(uint256 positionId, uint256 amount, uint256 takerMargin, uint256 makerMargin, uint256 value, int256 fundingPayment, uint256 interestPayment);
}

