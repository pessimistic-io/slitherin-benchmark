// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./SafeCast.sol";
import "./SignedSafeMath.sol";
import "./TransferHelper.sol";
//import "../interfaces/IERC20.sol";
import "./MarketStorage.sol";
import "./IMarketLogic.sol";
import "./IManager.sol";
import "./IPool.sol";
import "./IFundingLogic.sol";
import "./IInviteManager.sol";

/// @notice A market represents a perpetual trading market, eg. BTC_USDT (USDT settled).
/// YFX.com provides a diverse perpetual contracts including two kinds of position model, which are one-way position and
/// the hedging positiion mode, as well as three kinds of perpetual contracts, which are the linear contracts, the inverse contracts and the quanto contracts.

contract Market is MarketStorage, ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SignedSafeMath for int8;
    using SafeCast for int256;
    using SafeCast for uint256;

    constructor(address _manager, address _marketLogic, address _fundingLogic){
        //require(_manager != address(0) && _marketLogic != address(0) && _fundingLogic != address(0), "Market: address is zero address");
        require(_manager != address(0) && _marketLogic != address(0), "C0");
        manager = _manager;
        marketLogic = _marketLogic;
        fundingLogic = _fundingLogic;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "O0");
        _;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "O1");
        _;
    }

    modifier onlyRouter() {
        require(IManager(manager).checkRouter(msg.sender), "O2");
        _;
    }

    modifier whenNotCreateOrderPaused() {
        require(!marketConfig.createOrderPaused, "W0");
        _;
    }

    modifier whenNotSetTPSLPricePaused() {
        require(!marketConfig.setTPSLPricePaused, "W1");
        _;
    }

    modifier whenUpdateMarginPaused() {
        require(!marketConfig.updateMarginPaused, "W2");
        _;
    }

    /// @notice initialize market, only manager can call
    /// @param _token actually the price key, eg. "BTC_USDT"
    /// @param _marginAsset  margin asset address
    /// @param _pool pool address
    /// @param _marketType market type: {0: linear, 1: inverse, 2: quanto}
    function initialize(string memory _token, address _marginAsset, address _pool, uint8 _marketType) external {
        require(msg.sender == manager && _marginAsset != address(0) && _pool != address(0), "Market: Must be manager or valid address");
        token = _token;
        marginAsset = _marginAsset;
        pool = _pool;
        marketType = _marketType;
        emit Initialize(_token, _marginAsset, _pool, _marketType);
    }

    /// @notice set market params, only controller can call
    /// @param _marketLogic market logic address
    /// @param _fundingLogic funding logic address
    function modifyLogicAddresses(
        address _marketLogic,
        address _fundingLogic
    ) external onlyController {
        require(_marketLogic != address(0), "Market: invalid address");
        if (fundingLogic != address(0)) {
            require(_fundingLogic != address(0), "Market: invalid address");
        }
        marketLogic = _marketLogic;
        fundingLogic = _fundingLogic;
        emit LogicAddressesModified(marketLogic, fundingLogic);
    }

    /// @notice set general market configurations, only controller can call
    /// @param _config configuration parameters
    function setMarketConfig(MarketDataStructure.MarketConfig memory _config) external onlyManager {
        marketConfig = _config;
        emit SetMarketConfig(marketConfig);
    }

    /// @notice switch position mode, users can choose the one-way or hedging positon mode for a specific market
    /// @param _taker taker address
    /// @param _mode mode {0: one-way, 1: hedging}
    function switchPositionMode(address _taker, MarketDataStructure.PositionMode _mode) external onlyRouter {
        positionModes[_taker] = _mode;
        emit SwitchPositionMode(_taker, _mode);
    }

    /// @notice create a new order
    /// @param params order parameters
    /// @return id order id
    function createOrder(MarketDataStructure.CreateInternalParams memory params) external nonReentrant onlyRouter whenNotCreateOrderPaused returns (uint256 id) {
        return _createOrder(params);
    }

    function _createOrder(MarketDataStructure.CreateInternalParams memory params) internal returns (uint256) {
        MarketDataStructure.Order memory order = IMarketLogic(marketLogic).createOrderInternal(params);
        order.id = order.orderType == MarketDataStructure.OrderType.Open || order.orderType == MarketDataStructure.OrderType.Close ? ++orderID : ++triggerOrderID;

        orders[order.id] = order;
        takerOrderList[params._taker].push(order.id);

        if (!params.isLiquidate) takerOrderNum[params._taker][order.orderType] ++;
        _setTakerOrderTotalValue(order.taker, order.orderType, order.direction, order.freezeMargin.mul(order.takerLeverage).toInt256());


        if (!params.isLiquidate) IMarketLogic(marketLogic).checkOrder(order.id);
        return order.id;
    }

    struct ExecuteOrderInternalParams {
        uint256 price;
        bytes32 code;
        address inviter;
        uint256 discountRate;
        uint256 inviteRate;
        MarketDataStructure.Order order;
        MarketDataStructure.Position position;
        MarketDataStructure.Position oldPosition;
        MarketDataStructure.TradeResponse response;
        uint256 errorCode;
        address inviteManager;
        int256 settleDustMargin;            // dust margin part to be settled
    }

    /// @notice execute an order
    /// @param _id order id
    /// @return resultCode execute result 0：open success；1:order open fail；2:trigger order open fail
    /// @return _positionId position id
    function executeOrder(uint256 _id) external nonReentrant onlyRouter returns (int256 resultCode, uint256 _positionId) {
        ExecuteOrderInternalParams memory params;
        params.order = orders[_id];
        //freezeMargin > 0 ,order type is open and position direction is same as order direction;freezeMargin = 0,order type is close and position direction is neg of order direction

        int8 positionDirection;
        if (isOpenOrder(params.order.orderType)) {
            positionDirection = params.order.direction;
        } else {
            positionDirection = params.order.direction.neg256().toInt8();
        }
        MarketDataStructure.PositionKey key = getPositionKey(params.order.taker, positionDirection);
        _positionId = takerPositionList[params.order.taker][key];
        if (_positionId == 0) {
            _positionId = ++positionID;
            takerPositionList[params.order.taker][key] = _positionId;
        }

        //store position last funding rate
        orders[_id].frLastX96 = takerPositions[_positionId].frLastX96;
        //store position last funding amount
        orders[_id].fundingAmount = takerPositions[_positionId].amount.toInt256().mul(takerPositions[_positionId].direction);

        IPool(pool).updateBorrowIG();
        _settleFunding(takerPositions[_positionId]);

        params.oldPosition = takerPositions[_positionId];

        params.inviteManager = IManager(manager).inviteManager();
        (params.code, params.inviter, params.discountRate, params.inviteRate) = IInviteManager(params.inviteManager).getReferrerCodeByTaker(orders[_id].taker);

        if (params.order.orderType == MarketDataStructure.OrderType.Open || params.order.orderType == MarketDataStructure.OrderType.Close) {
            lastExecutedOrderId = _id;
        }
        (params.order, params.position, params.response, params.errorCode) = IMarketLogic(marketLogic).trade(_id, _positionId, params.discountRate, params.inviteRate);
        if (params.errorCode != 0) {
            emit ExecuteOrderError(_id, params.errorCode);
            if (params.errorCode == 5) {
                return (2, _positionId);
            }
            orders[_id].status = MarketDataStructure.OrderStatus.OpenFail;
            return (1, _positionId);
        }

        params.order.code = params.code;
//        if (params.order.freezeMargin > 0) TransferHelper.safeTransfer(marginAsset,IManager(manager).vault(), params.order.freezeMargin);
        if (params.order.freezeMargin > 0) _transfer(IManager(manager).vault(), params.order.freezeMargin);

        takerOrderNum[params.order.taker][params.order.orderType]--;
        _setTakerOrderTotalValue(params.order.taker, params.order.orderType, params.order.direction, params.order.freezeMargin.mul(params.order.takerLeverage).toInt256().neg256());


        if (params.position.amount < marketConfig.DUST && params.position.amount > 0) {
            params.settleDustMargin = params.position.takerMargin.toInt256().sub(params.position.fundingPayment).sub(params.response.leftInterestPayment.toInt256());
            if (params.settleDustMargin > 0) {
                params.response.toTaker = params.response.toTaker.add(params.settleDustMargin.toUint256());
            } else {
                params.order.rlzPnl = params.order.rlzPnl.add(params.settleDustMargin);
            }

            emit DustPositionClosed(
                params.order.taker,
                params.order.market,
                params.position.id,
                params.position.amount,
                params.position.takerMargin,
                params.position.makerMargin,
                params.position.value,
                params.position.fundingPayment,
                params.response.leftInterestPayment
            );

            params.order.interestPayment = params.order.interestPayment.add(params.response.leftInterestPayment);
            params.order.fundingPayment = params.order.fundingPayment.add(params.position.fundingPayment);

            params.position.fundingPayment = 0;
            params.position.takerMargin = 0;
            params.position.makerMargin = 0;
            params.position.debtShare = 0;
            params.position.amount = 0;
            params.position.value = 0;

            params.response.isIncreasePosition = false;
        }


        if (params.response.isIncreasePosition) {
            IPool(pool).openUpdate(IPool.OpenUpdateInternalParams(
                params.order.id,
                params.response.isDecreasePosition ? params.position.makerMargin : params.position.makerMargin.sub(params.oldPosition.makerMargin),
                params.response.isDecreasePosition ? params.position.takerMargin : params.position.takerMargin.sub(params.oldPosition.takerMargin),
                params.response.isDecreasePosition ? params.position.amount : params.position.amount.sub(params.oldPosition.amount),
                params.response.isDecreasePosition ? params.position.value : params.position.value.sub(params.oldPosition.value),
                params.response.isDecreasePosition ? 0 : params.order.feeToMaker,
                params.order.direction,
                params.order.freezeMargin,
                params.order.taker,
                params.response.isDecreasePosition ? 0 : params.order.feeToInviter,
                params.inviter,
                params.response.isDecreasePosition ? params.position.debtShare : params.position.debtShare.sub(params.oldPosition.debtShare),
                params.response.isDecreasePosition ? 0 : params.order.feeToExchange
            )
            );
        }

        if (params.response.isDecreasePosition) {
            IPool(pool).closeUpdate(
                IPool.CloseUpdateInternalParams(
                    params.order.id,
                    params.response.isIncreasePosition ? params.oldPosition.makerMargin : params.oldPosition.makerMargin.sub(params.position.makerMargin),
                    params.response.isIncreasePosition ? params.oldPosition.takerMargin : params.oldPosition.takerMargin.sub(params.position.takerMargin),
                    params.response.isIncreasePosition ? params.oldPosition.amount : params.oldPosition.amount.sub(params.position.amount),
                    params.response.isIncreasePosition ? params.oldPosition.value : params.oldPosition.value.sub(params.position.value),
                    params.order.rlzPnl.neg256(),
                    params.order.feeToMaker,
                    params.response.isIncreasePosition ? params.oldPosition.fundingPayment : params.oldPosition.fundingPayment.sub(params.position.fundingPayment),
                    params.oldPosition.direction,
                    params.response.isIncreasePosition ? 0 : params.order.freezeMargin,
                    params.response.isIncreasePosition ? params.oldPosition.debtShare : params.oldPosition.debtShare.sub(params.position.debtShare),
                    params.order.interestPayment,
                    params.oldPosition.isETH,
                    0,
                    params.response.toTaker,
                    params.order.taker,
                    params.order.feeToInviter,
                    params.inviter,
                    params.order.feeToExchange
                )
            );
        }

        IInviteManager(params.inviteManager).updateTradeValue(marketType, params.order.taker, params.inviter, params.response.tradeValue);

        emit ExecuteInfo(params.order.id, params.order.orderType, params.order.direction, params.order.taker, params.response.tradeValue, params.order.feeToDiscount, params.order.tradePrice);

        if (params.response.isIncreasePosition && !params.response.isDecreasePosition) {
            require(params.position.amount > params.oldPosition.amount, "EO0");
        } else if (!params.response.isIncreasePosition && params.response.isDecreasePosition) {
            require(params.position.amount < params.oldPosition.amount, "EO1");
        } else {
            require(params.position.direction != params.oldPosition.direction, "EO2");
        }

        orders[_id] = params.order;
        takerPositions[_positionId] = params.position;

        return (0, _positionId);
    }

    struct LiquidateInternalParams {
        IMarketLogic.LiquidateInfoResponse response;
        uint256 toTaker;
        bytes32 code;
        address inviter;
        uint256 discountRate;
        uint256 inviteRate;
        address inviteManager;
    }

    ///@notice liquidate position
    ///@param _id position id
    ///@param action liquidate type
    ///@return liquidate order id
    function liquidate(uint256 _id, MarketDataStructure.OrderType action) public nonReentrant onlyRouter returns (uint256) {
        LiquidateInternalParams memory params;
        MarketDataStructure.Position storage position = takerPositions[_id];
        require(position.amount > 0, "L0");

        //create liquidate order
        MarketDataStructure.Order storage order = orders[_createOrder(MarketDataStructure.CreateInternalParams(position.taker, position.id, 0, 0, 0, position.amount, position.takerLeverage, position.direction.neg256().toInt8(), 0, 0, 1, true, position.isETH))];
        order.frLastX96 = position.frLastX96;
        order.fundingAmount = position.amount.toInt256().mul(position.direction);
        //update interest rate
        IPool(pool).updateBorrowIG();
        //settle funding rate
        _settleFunding(position);
        order.frX96 = fundingGrowthGlobalX96;
        order.fundingPayment = position.fundingPayment;

        params.inviteManager = IManager(manager).inviteManager();
        (params.code, params.inviter, params.discountRate, params.inviteRate) = IInviteManager(params.inviteManager).getReferrerCodeByTaker(order.taker);
        //get liquidate info by marketLogic
        params.response = IMarketLogic(marketLogic).getLiquidateInfo(IMarketLogic.LiquidityInfoParams(position, action, params.discountRate, params.inviteRate));

        //update order info
        order.code = params.code;
        order.takerFee = params.response.takerFee;
        order.feeToMaker = params.response.feeToMaker;
        order.feeToExchange = params.response.feeToExchange;
        order.feeToInviter = params.response.feeToInviter;
        order.feeToDiscount = params.response.feeToDiscount;
        order.orderType = action;
        order.interestPayment = params.response.payInterest;
        order.riskFunding = params.response.riskFunding;
        order.rlzPnl = params.response.pnl;
        order.status = MarketDataStructure.OrderStatus.Opened;
        order.tradeTs = block.timestamp;
        order.tradePrice = params.response.price;
        order.tradeIndexPrice= params.response.indexPrice;

        //liquidate position，update close position info in pool
        IPool(pool).closeUpdate(
            IPool.CloseUpdateInternalParams(
                order.id,
                position.makerMargin,
                position.takerMargin,
                position.amount,
                position.value,
                params.response.pnl.neg256(),
                params.response.feeToMaker,
                position.fundingPayment,
                position.direction,
                0,
                position.debtShare,
                params.response.payInterest,
                position.isETH,
                order.riskFunding,
                params.response.toTaker,
                position.taker,
                order.feeToInviter,
                params.inviter,
                order.feeToExchange
            )
        );

        //emit invite info
        if (order.orderType != MarketDataStructure.OrderType.Liquidate) {
            IInviteManager(params.inviteManager).updateTradeValue(marketType, order.taker, params.inviter, params.response.tradeValue);
        }
        
        emit ExecuteInfo(order.id, order.orderType, order.direction, order.taker, params.response.tradeValue, order.feeToDiscount, order.tradePrice);

        //update position info
        position.amount = 0;
        position.makerMargin = 0;
        position.takerMargin = 0;
        position.value = 0;
        //position cumulative rlz pnl
        position.pnl = position.pnl.add(order.rlzPnl);
        position.fundingPayment = 0;
        position.lastUpdateTs = 0;
        position.stopLossPrice = 0;
        position.takeProfitPrice = 0;
        position.lastTPSLTs = 0;
        //clear position debt share
        position.debtShare = 0;

        return order.id;
    }

    ///@notice update market funding rate
    function updateFundingGrowthGlobal() external {
        _updateFundingGrowthGlobal();
    }

    ///@notice update market funding rate
    ///@param position taker position
    ///@return _fundingPayment
    function _settleFunding(MarketDataStructure.Position storage position) internal returns (int256 _fundingPayment){
        /// @notice once funding logic address set, address(0) is not allowed to use
        if (fundingLogic == address(0)) {
            return 0;
        }
        _updateFundingGrowthGlobal();
        _fundingPayment = IFundingLogic(fundingLogic).getFundingPayment(address(this), position.id, fundingGrowthGlobalX96);
        if (block.timestamp != lastFrX96Ts) {
            lastFrX96Ts = block.timestamp;
        }
        position.frLastX96 = fundingGrowthGlobalX96;
        if (_fundingPayment != 0) {
            position.fundingPayment = position.fundingPayment.add(_fundingPayment);
            IPool(pool).updateFundingPayment(address(this), _fundingPayment);
        }
    }

    ///@notice update market funding rate
    function _updateFundingGrowthGlobal() internal {
        //calc current funding rate by fundingLogic
        if (fundingLogic != address(0)) {
            fundingGrowthGlobalX96 = IFundingLogic(fundingLogic).getFunding(address(this));
        }
    }

    ///@notice cancel order, only router can call
    ///@param _id order id
    function cancel(uint256 _id) external nonReentrant onlyRouter {
        MarketDataStructure. Order storage order = orders[_id];
        require(order.status == MarketDataStructure.OrderStatus.Open || order.status == MarketDataStructure.OrderStatus.OpenFail, "Market:not open");
        order.status = MarketDataStructure.OrderStatus.Canceled;
        //reduce taker order count
        takerOrderNum[order.taker][order.orderType]--;
        _setTakerOrderTotalValue(order.taker, order.orderType, order.direction, order.freezeMargin.mul(order.takerLeverage).toInt256().neg256());
//        if (order.freezeMargin > 0)TransferHelper.safeTransfer(marginAsset,msg.sender, order.freezeMargin);
        if (order.freezeMargin > 0) _transfer(msg.sender, order.freezeMargin);
    }

    function _setTakerOrderTotalValue(address _taker, MarketDataStructure.OrderType orderType, int8 _direction, int256 _value) internal {
        if (isOpenOrder(orderType)) {
            _value = _value.mul(AMOUNT_PRECISION).div(marketConfig.marketAssetPrecision.toInt256());
            //reduce taker order total value
            takerOrderTotalValues[_taker][_direction] = takerOrderTotalValues[_taker][_direction].add(_value);
        }
    }

    ///@notice set order stop profit and loss price, only router can call
    ///@param _id position id
    ///@param _profitPrice take profit price
    ///@param _stopLossPrice stop loss price
    function setTPSLPrice(uint256 _id, uint256 _profitPrice, uint256 _stopLossPrice) external onlyRouter whenNotSetTPSLPricePaused {
        takerPositions[_id].takeProfitPrice = _profitPrice;
        takerPositions[_id].stopLossPrice = _stopLossPrice;
        takerPositions[_id].lastTPSLTs = block.timestamp;
    }

    ///@notice increase or decrease taker margin, only router can call
    ///@param _id position id
    ///@param _updateMargin increase or decrease margin
    function updateMargin(uint256 _id, uint256 _updateMargin, bool isIncrease) external nonReentrant onlyRouter whenUpdateMarginPaused {
        MarketDataStructure.Position storage position = takerPositions[_id];
        int256 _deltaMargin;
        if (isIncrease) {
            position.takerMargin = position.takerMargin.add(_updateMargin);
            _deltaMargin = _updateMargin.toInt256();
        } else {
            position.takerMargin = position.takerMargin.sub(_updateMargin);
            _deltaMargin = _updateMargin.toInt256().neg256();
        }

        //update taker margin in pool
        IPool(pool).takerUpdateMargin(address(this), position.taker, _deltaMargin, position.isETH);
        emit UpdateMargin(_id, _deltaMargin);
    }

    function _transfer(address to, uint256 amount) internal {
        TransferHelper.safeTransfer(marginAsset, to, amount);
    }

    function isOpenOrder(MarketDataStructure.OrderType orderType) internal pure returns (bool) {
        return orderType == MarketDataStructure.OrderType.Open || orderType == MarketDataStructure.OrderType.TriggerOpen;
    }

    ///@notice get taker position id
    ///@param _taker taker address
    ///@param _direction position direction
    ///@return position id
    function getPositionId(address _taker, int8 _direction) public view returns (uint256) {
        return takerPositionList[_taker][getPositionKey(_taker, _direction)];
    }

    function getPositionKey(address _taker, int8 _direction) internal view returns (MarketDataStructure.PositionKey key) {
        //if position mode is oneway,position key is 2,else if direction is 1,position key is 1,else position key is 0
        if (positionModes[_taker] == MarketDataStructure.PositionMode.OneWay) {
            key = MarketDataStructure.PositionKey.OneWay;
        } else {
            key = _direction == - 1 ? MarketDataStructure.PositionKey.Short : MarketDataStructure.PositionKey.Long;
        }
    }

    function getPosition(uint256 _id) external view returns (MarketDataStructure.Position memory) {
        return takerPositions[_id];
    }

    function getOrderIds(address _taker) external view returns (uint256[] memory) {
        return takerOrderList[_taker];
    }

    function getOrder(uint256 _id) external view returns (MarketDataStructure.Order memory) {
        return orders[_id];
    }

    function getLogicAddress() external view returns (address){
        return fundingLogic;
    }

    function getMarketConfig() external view returns (MarketDataStructure.MarketConfig memory){
        return marketConfig;
    }
}

