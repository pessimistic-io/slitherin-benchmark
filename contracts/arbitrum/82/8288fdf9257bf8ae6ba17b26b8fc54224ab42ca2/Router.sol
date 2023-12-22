// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./PoolDataStructure.sol";
import "./MarketDataStructure.sol";
import "./TransferHelper.sol";
import "./IManager.sol";
import "./IERC20.sol";
import "./IWrappedCoin.sol";
import "./IMarket.sol";
import "./IRiskFunding.sol";
import "./IPool.sol";
import "./IFundingLogic.sol";
import "./IFastPriceFeed.sol";
import "./IInviteManager.sol";
import "./IMarketLogic.sol";
import "./IRewardRouter.sol";

contract Router {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public batchExecuteLimit = 10;  //max batch execution orders limit
    address public manager;
    address fastPriceFeed;
    address riskFunding;
    address inviteManager;
    address marketLogic;
    address rewardRouter;

    //taker => market => orderId[]
    mapping(address => mapping(address => EnumerableSet.UintSet)) internal notExecuteOrderIds; // not executed order ids
    address public WETH;


    event TakerOpen(address market, uint256 id);
    event Open(address market, uint256 id, uint256 orderid);
    event TakerClose(address market, uint256 id);
    event Liquidate(address market, uint256 id, uint256 orderid, address liquidator);
    event TakeProfit(address market, uint256 id, uint256 orderid);
    event Cancel(address market, uint256 id);
    event ChangeStatus(address market, uint256 id);
    event AddLiquidity(uint256 id, address pool, uint256 amount);
    event RemoveLiquidity(uint256 id, address pool, uint256 liquidity);
    event ExecuteAddLiquidityOrder(uint256 id, address pool);
    event ExecuteRmLiquidityOrder(uint256 id, address pool);
    event SetStopProfitAndLossPrice(uint256 id, address market, uint256 _profitPrice, uint256 _stopLossPrice);
    event SetParams(address _fastPriceFeed, address _riskFunding, address _inviteManager, address _marketLogic, uint256 _batchExecuteLimit);

    constructor(address _manager, address _WETH) {
        manager = _manager;
        WETH = _WETH;
    }

    modifier whenNotPaused() {
        require(!IManager(manager).paused(), "Market:system paused");
        _;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "Router: Must be controller");
        _;
    }

    modifier onlyPriceProvider() {
        require(IManager(manager).checkSigner(msg.sender), "Router: caller is not the price provider");
        _;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'Router: EXPIRED');
        _;
    }

    modifier validateMarket(address _market){
        require(IManager(manager).checkMarket(_market), "Router: market not registered");
        _;
    }

    modifier validatePool(address _pool){
        require(IManager(manager).checkPool(_pool), "Router: pool not registered");
        _;
    }

    /// @notice set params, only controller can call
    /// @param _fastPriceFeed fast price feed contract address
    /// @param _riskFunding risk funding contract address
    /// @param _inviteManager invite manager contract address
    /// @param _marketLogic market logic contract address
    /// @param _batchExecuteLimit max batch execute limit
    function setConfigParams(address _fastPriceFeed, address _riskFunding, address _inviteManager, address _marketLogic, address _rewardRouter, uint256 _batchExecuteLimit) external onlyController {
        require(_fastPriceFeed != address(0) && _riskFunding != address(0) && _inviteManager != address(0) && _marketLogic != address(0) && _batchExecuteLimit > 0, "Router: error params");
        fastPriceFeed = _fastPriceFeed;
        riskFunding = _riskFunding;
        inviteManager = _inviteManager;
        marketLogic = _marketLogic;
        rewardRouter = _rewardRouter;
        batchExecuteLimit = _batchExecuteLimit;
        emit SetParams(_fastPriceFeed, _riskFunding, _inviteManager, _marketLogic, _batchExecuteLimit);
    }

    /// @notice user open position parameters
    struct TakerOpenParams {
        address _market;            // market contract address
        bytes32 inviterCode;        // inviter code
        uint128 minPrice;           // min price for the slippage
        uint128 maxPrice;           // max price for the slippage
        uint256 margin;             // margin of this order
        uint16 leverage;
        int8 direction;             // order direction, 1: long, -1: short
        int8 triggerDirection;      // trigger flag {1: index price >= trigger price, -1: index price <= trigger price}
        uint256 triggerPrice;
        uint256 deadline;
    }

    /// @notice user close position parameters
    struct TakerCloseParams {
        address _market;            // market contract address
        uint256 id;                 // position id
        bytes32 inviterCode;        // inviter code
        uint128 minPrice;           // min price for the slippage
        uint128 maxPrice;           // max price for the slippage
        uint256 amount;             // position amount to close
        int8 triggerDirection;      // trigger flag {1: index price >= trigger price, -1: index price <= trigger price}
        uint256 triggerPrice;
        uint256 deadline;
    }

    /// @notice place an open-position order, margined by erc20 tokens
    /// @param params order params, detailed in the data structure declaration
    /// @return id order id
    function takerOpen(TakerOpenParams memory params) external payable ensure(params.deadline) validateMarket(params._market) returns (uint256 id) {
        address marginAsset = getMarketMarginAsset(params._market);
        uint256 executeOrderFee = getExecuteOrderFee();
        require(IERC20(marginAsset).balanceOf(msg.sender) >= params.margin, "Router: insufficient balance");
        require(IERC20(marginAsset).allowance(msg.sender, address(this)) >= params.margin, "Router: insufficient allowance");
        require(msg.value == executeOrderFee, "Router: inaccurate msg.value");

        TransferHelper.safeTransferFrom(marginAsset, msg.sender, params._market, params.margin);
        id = _takerOpen(params, false);
    }

    /// @notice place an open-position order margined by ETH
    /// @param params order params, detailed in the data structure declaration
    /// @return id order id
    function takerOpenETH(TakerOpenParams memory params) external payable ensure(params.deadline) validateMarket(params._market) returns (uint256 id) {
        address marginAsset = getMarketMarginAsset(params._market);
        /// @notice important can not remove
        require(marginAsset == WETH, "Router: margin asset of this market is not WETH");

        uint256 executeOrderFee = getExecuteOrderFee();
        require(msg.value == params.margin.add(executeOrderFee), "Router: inaccurate value");

        IWrappedCoin(WETH).deposit{value: params.margin}();
        TransferHelper.safeTransfer(WETH, params._market, params.margin);

        id = _takerOpen(params, true);
    }

    function _takerOpen(TakerOpenParams memory params, bool isETH) internal whenNotPaused returns (uint256 id) {
        require(params.minPrice <= params.maxPrice, "Router: slippage price error");

        setReferralCode(params.inviterCode);

        id = IMarket(params._market).createOrder(MarketDataStructure.CreateInternalParams({
            _taker: msg.sender,
            id: 0,
            minPrice: params.minPrice,
            maxPrice: params.maxPrice,
            margin: params.margin,
            amount: 0,
            leverage: params.leverage,
            direction: params.direction,
            triggerDirection: params.triggerDirection,
            triggerPrice: params.triggerPrice,
            reduceOnly: 0,
            isLiquidate: false,
            isETH: isETH
        }));
        EnumerableSet.add(notExecuteOrderIds[msg.sender][params._market], id);
        emit TakerOpen(params._market, id);
    }

    /// @notice place a close-position order
    /// @param params order parameters, detailed in the data structure declaration
    /// @return id order id
    function takerClose(TakerCloseParams memory params) external payable ensure(params.deadline) validateMarket(params._market) whenNotPaused returns (uint256 id){
        require(params.minPrice <= params.maxPrice, "Router: slippage price error");
        uint256 executeOrderFee = getExecuteOrderFee();
        require(msg.value == executeOrderFee, "Router: insufficient execution fee");

        setReferralCode(params.inviterCode);

        id = IMarket(params._market).createOrder(MarketDataStructure.CreateInternalParams({
            _taker: msg.sender,
            id: params.id,
            minPrice: params.minPrice,
            maxPrice: params.maxPrice,
            margin: 0,
            amount: params.amount,
            leverage: 0,
            direction: 0,
            triggerDirection: params.triggerDirection,
            triggerPrice: params.triggerPrice,
            reduceOnly: 1,
            isLiquidate: false,
            isETH: false
        }));
        EnumerableSet.add(notExecuteOrderIds[msg.sender][params._market], id);
        emit TakerClose(params._market, id);
    }

    /// @notice batch execution of orders
    /// @param _market market contract address
    /// @param _ids trigger order ids
    /// @param _tokens index token name array
    /// @param _prices token prices array
    /// @param _timestamps token prices timestamps array
    function batchExecuteOrder(
        address _market,
        uint256[] memory _ids,
        string[] memory _tokens,
        uint128[] memory _prices,
        uint32[] memory _timestamps
    ) external onlyPriceProvider validateMarket(_market) {
        setPrices(_tokens, _prices, _timestamps);
        // execute trigger orders
        uint256 maxExecuteOrderNum;
        if (_ids.length > batchExecuteLimit) {
            maxExecuteOrderNum = batchExecuteLimit;
        } else {
            maxExecuteOrderNum = _ids.length;
        }
        for (uint256 i = 0; i < maxExecuteOrderNum; i++) {
            MarketDataStructure.Order memory order = IMarket(_market).getOrder(_ids[i]);
            if (order.orderType == MarketDataStructure.OrderType.TriggerOpen || order.orderType == MarketDataStructure.OrderType.TriggerClose) {
                _executeOrder(order, msg.sender);
            }
        }

        // execute market orders (non-trigger)
        (uint256 start,uint256 end) = getLastExecuteOrderId(_market);
        for (uint256 i = start; i < end; i++) {
            MarketDataStructure.Order memory order = IMarket(_market).getOrder(i);
            _executeOrder(order, msg.sender);
        }
    }

    /// @notice batch execution of orders by the community, only market orders supported
    /// @param _market market contract address
    function batchExecuteOrderByCommunity(address _market) external validateMarket(_market) {
        // execute market orders
        (uint256 start,uint256 end) = getLastExecuteOrderId(_market);
        for (uint256 i = start; i < end; i++) {
            MarketDataStructure.Order memory order = IMarket(_market).getOrder(i);
            if (
                order.orderType != MarketDataStructure.OrderType.TriggerOpen &&
                order.orderType != MarketDataStructure.OrderType.TriggerClose &&
                block.timestamp > order.createTs.add(IManager(manager).communityExecuteOrderDelay())
            ) {
                _executeOrder(order, msg.sender);
            }
        }
    }

    /// @notice execute an order
    /// @param order  order info
    /// @param to the address to receive the execution fee
    function _executeOrder(MarketDataStructure.Order memory order, address to) internal {
        if (order.status == MarketDataStructure.OrderStatus.Open) {
            (int256 resultCode,uint256 positionId) = IMarket(order.market).executeOrder(order.id);
            if (resultCode == 0) EnumerableSet.remove(notExecuteOrderIds[order.taker][order.market], order.id);
            if (resultCode == 0 || resultCode == 1) {
                TransferHelper.safeTransferETH(to, order.executeFee);
            }
            emit Open(order.market, positionId, order.id);
        }
    }

    /// @notice execute position liquidation, take profit and tpsl
    /// @param _market  market contract address
    /// @param id   position id
    /// @param action   reason and how to end the position
    /// @param _tokens  price tokens
    /// @param _prices  price
    /// @param _timestamps   price timestamp array
    function liquidate(address _market, uint256 id, MarketDataStructure.OrderType action, string[] memory _tokens, uint128[] memory _prices, uint32[] memory _timestamps) external validateMarket(_market) {
        require(IManager(manager).checkLiquidator(msg.sender), "Router: only liquidators");
        setPrices(_tokens, _prices, _timestamps);
        uint256 orderId = IMarket(_market).liquidate(id, action);
        if (MarketDataStructure.OrderType.Liquidate == action) {
            IRiskFunding(riskFunding).updateLiquidatorExecutedFee(msg.sender);
        }
        emit Liquidate(_market, id, orderId, msg.sender);
    }

    /// @notice execute position liquidation
    /// @param _market  market contract address
    /// @param id   position id
    function liquidateByCommunity(address _market, uint256 id) external validateMarket(_market) {
        uint256 orderId = IMarket(_market).liquidate(id, MarketDataStructure.OrderType.Liquidate);
        IRiskFunding(riskFunding).updateLiquidatorExecutedFee(msg.sender);
        emit Liquidate(_market, id, orderId, msg.sender);
    }

    /// @notice  increase margin to a position, margined by ETH
    /// @param _market  market contract address
    /// @param _id  position id
    function increaseMarginETH(address _market, uint256 _id) external payable validateMarket(_market) {
        address vault = IManager(manager).vault();
        address marginAsset = getMarketMarginAsset(_market);
        /// @notice important, can not remove, or 100 ETH can be used as 100 USDC
        require(marginAsset == WETH, "Router: margin is not WETH");
        IWrappedCoin(WETH).deposit{value: msg.value}();
        TransferHelper.safeTransfer(WETH, vault, msg.value);
        _updateMargin(_market, _id, msg.value, true);
    }

    /// @notice  add margin to a position, margined by ERC20 tokens
    /// @param _market  market contract address
    /// @param _id  position id
    /// @param _value  add margin value
    function increaseMargin(address _market, uint256 _id, uint256 _value) external validateMarket(_market) {
        address marginAsset = getMarketMarginAsset(_market);
        address vault = IManager(manager).vault();
        TransferHelper.safeTransferFrom(marginAsset, msg.sender, vault, _value);
        _updateMargin(_market, _id, _value, true);
    }

    /// @notice  remove margin from a position
    /// @param _market  market contract address
    /// @param _id  position id
    /// @param _value  remove margin value
    function decreaseMargin(address _market, uint256 _id, uint256 _value) external validateMarket(_market) {
        _updateMargin(_market, _id, _value, false);
    }

    function _updateMargin(address _market, uint256 _id, uint256 _deltaMargin, bool isIncrease) internal whenNotPaused {
        require(_deltaMargin != 0, "Router: wrong value for remove margin");
        MarketDataStructure.Position memory position = IMarket(_market).getPosition(_id);
        MarketDataStructure.MarketConfig memory marketConfig = IMarket(_market).getMarketConfig();
        require(position.taker == msg.sender, "Router: caller is not owner");
        require(position.amount > 0, "Router: position not exist");

        if (isIncrease) {
            position.takerMargin = position.takerMargin.add(_deltaMargin);
            require(position.takerMargin <= marketConfig.takerMarginMax && position.makerMargin >= position.takerMargin, 'Router: margin exceeded limit');
        } else {
            //get max decrease margin amount
            (uint256 maxDecreaseMargin) = IMarketLogic(marketLogic).getMaxTakerDecreaseMargin(position);
            if (maxDecreaseMargin < _deltaMargin) _deltaMargin = maxDecreaseMargin;
            position.takerMargin = position.takerMargin.sub(_deltaMargin);
        }

        IMarket(_market).updateMargin(_id, _deltaMargin, isIncrease);
    }

    /// @notice user or system cancel an order that open or failed
    /// @param _market market address
    /// @param id order id
    function orderCancel(address _market, uint256 id) external validateMarket(_market) {
        address marginAsset = getMarketMarginAsset(_market);
        MarketDataStructure.Order memory order = IMarket(_market).getOrder(id);
        if (!IManager(manager).checkSigner(msg.sender)) {
            require(order.taker == msg.sender, "Router: not owner");
            require(order.createTs.add(IManager(manager).cancelElapse()) <= block.timestamp, "Router: can not cancel until deadline");
        }

        IMarket(_market).cancel(id);
        if (order.freezeMargin > 0) {
            if (!order.isETH) {
                TransferHelper.safeTransfer(marginAsset, order.taker, order.freezeMargin);
            } else {
                IWrappedCoin(marginAsset).withdraw(order.freezeMargin);
                TransferHelper.safeTransferETH(order.taker, order.freezeMargin);
            }
        }

        if (order.status == MarketDataStructure.OrderStatus.Open)
            TransferHelper.safeTransferETH(order.taker, order.executeFee);
        EnumerableSet.remove(notExecuteOrderIds[order.taker][_market], id);
        emit Cancel(_market, id);
    }

    /// @notice user set prices for take-profit and stop-loss
    /// @param _market  market contract address
    /// @param _id  position id
    /// @param _profitPrice take-profit price
    /// @param _stopLossPrice stop-loss price
    function setTPSLPrice(address _market, uint256 _id, uint256 _profitPrice, uint256 _stopLossPrice) external validateMarket(_market) whenNotPaused {
        MarketDataStructure.Position memory position = IMarket(_market).getPosition(_id);
        require(position.taker == msg.sender, "Router: not taker");
        require(position.amount > 0, "Router: no position");
        IMarket(_market).setTPSLPrice(_id, _profitPrice, _stopLossPrice);
        emit SetStopProfitAndLossPrice(_id, _market, _profitPrice, _stopLossPrice);
    }

    /// @notice user modify position mode
    /// @param _market  market contract address
    /// @param _mode  position mode
    function switchPositionMode(address _market, MarketDataStructure.PositionMode _mode) external validateMarket(_market) {
        IMarketLogic(IMarket(_market).marketLogic()).checkSwitchMode(_market, msg.sender, _mode);
        IMarket(_market).switchPositionMode(msg.sender, _mode);
    }

    /// @notice update offChain price by price provider
    /// @param _tokens  index token name array
    /// @param _prices  price array
    /// @param _timestamps  timestamp array
    function setPrices(string[] memory _tokens, uint128[] memory _prices, uint32[] memory _timestamps) public onlyPriceProvider {
        IFastPriceFeed(fastPriceFeed).setPrices(_tokens, _prices, _timestamps);
    }

    /// @notice add liquidity to the pool by using ETH
    /// @param _pool  the pool to add liquidity
    /// @param _amount the amount to add liquidity
    /// @param _deadline the deadline time to add liquidity order
    function addLiquidityETH(address _pool, uint256 _amount, bool isStakeLp, uint256 _deadline) external payable ensure(_deadline) validatePool(_pool) returns (bool result, uint256 id){
        address baseAsset = IPool(_pool).getBaseAsset();
        require(baseAsset == WETH, "Router: baseAsset is not WETH");
        require(msg.value == _amount, "Router: inaccurate balance");
        IWrappedCoin(WETH).deposit{value: msg.value}();
        TransferHelper.safeTransfer(WETH, IManager(manager).vault(), msg.value);
        (uint256 _id) = IPool(_pool).addLiquidity(msg.sender, _amount);
        result = true;
        id = _id;
        emit AddLiquidity(_id, _pool, _amount);

        _executeLiquidityOrder(_pool, _id, true, isStakeLp);
    }


    /// @notice add liquidity to the pool by using ERC20 tokens
    /// @param _pool  the pool to add liquidity
    /// @param _amount the amount to add liquidity
    /// @param _deadline the deadline time to add liquidity order
    function addLiquidity(address _pool, uint256 _amount, bool isStakeLp, uint256 _deadline) external ensure(_deadline) validatePool(_pool) returns (bool result, uint256 id){
        address baseAsset = IPool(_pool).getBaseAsset();
        require(IERC20(baseAsset).balanceOf(msg.sender) >= _amount, "Router: insufficient balance");
        require(IERC20(baseAsset).allowance(msg.sender, address(this)) >= _amount, "Router: insufficient allowance");
        TransferHelper.safeTransferFrom(baseAsset, msg.sender, IManager(manager).vault(), _amount);
        (uint256 _id) = IPool(_pool).addLiquidity(msg.sender, _amount);
        result = true;
        id = _id;

        emit AddLiquidity(_id, _pool, _amount);

        _executeLiquidityOrder(_pool, _id, false, isStakeLp);
    }

    /// @notice execute liquidity orders
    /// @param _pool pool address
    /// @param _id liquidity order id
    function _executeLiquidityOrder(address _pool, uint256 _id, bool isETH, bool isStake) internal {
        //IPool(_pool).updateBorrowIG();
        PoolDataStructure.MakerOrder memory order = IPool(_pool).getOrder(_id);
        if (order.action == PoolDataStructure.PoolAction.Deposit) {
            (uint256 liquidity) = IPool(_pool).executeAddLiquidityOrder(_id);
            if (isStake && rewardRouter != address(0)) {
                IRewardRouter(rewardRouter).stakeLpForAccount(order.maker, _pool, liquidity);
            }
            emit ExecuteAddLiquidityOrder(_id, _pool);
        } else {
            IPool(_pool).executeRmLiquidityOrder(_id, isETH);
            emit ExecuteRmLiquidityOrder(_id, _pool);
        }
    }

    /// @notice remove liquidity from the pool, get ERC20 tokens
    /// @param _pool  which pool address to remove liquidity
    /// @param _liquidity liquidity amount to remove
    /// @param _deadline deadline time
    /// @return result result of cancel the order
    /// @return id order id for remove liquidity
    function removeLiquidity(address _pool, uint256 _liquidity, bool isUnStake, uint256 _deadline) external ensure(_deadline) validatePool(_pool) returns (bool result, uint256 id){
        if (isUnStake && rewardRouter != address(0)) {
            uint256 lpBalance = IERC20(_pool).balanceOf(msg.sender);
            if (lpBalance < _liquidity) {
                IRewardRouter(rewardRouter).unstakeLpForAccount(msg.sender, _pool, _liquidity.sub(lpBalance));
            }
        }

        (uint256 _id, uint256 _value) = IPool(_pool).removeLiquidity(msg.sender, _liquidity);
        result = true;
        id = _id;
        emit RemoveLiquidity(_id, _pool, _value);

        _executeLiquidityOrder(_pool, _id, false, false);
    }


    /// @notice execute remove liquidity orders, get ETH if and only if the base asset of the pool is WETH
    /// @param _pool  which pool address to remove liquidity
    /// @param _liquidity liquidity amount to remove
    /// @param _deadline deadline time
    /// @return result result of cancel the order
    /// @return id order id for remove liquidity
    function removeLiquidityETH(address _pool, uint256 _liquidity, bool isUnStake, uint256 _deadline) external ensure(_deadline) validatePool(_pool) returns (bool result, uint256 id){
        require(IPool(_pool).getBaseAsset() == WETH, "Router: baseAsset is not WETH");

        if (isUnStake && rewardRouter != address(0)) {
            uint256 lpBalance = IERC20(_pool).balanceOf(msg.sender);
            if (lpBalance < _liquidity) {
                IRewardRouter(rewardRouter).unstakeLpForAccount(msg.sender, _pool, _liquidity.sub(lpBalance));
            }
        }

        (uint256 _id, uint256 _value) = IPool(_pool).removeLiquidity(msg.sender, _liquidity);
        result = true;
        id = _id;
        emit RemoveLiquidity(_id, _pool, _value);

        _executeLiquidityOrder(_pool, _id, true, false);
    }

    /// @notice set the referral code for the trader
    /// @param inviterCode the inviter code
    function setReferralCode(bytes32 inviterCode) internal {
        IInviteManager(inviteManager).setTraderReferralCode(msg.sender, inviterCode);
    }

    /// @notice calculate the execution order ids
    /// @param _market market address
    /// @return start start order id
    /// @return end end order id
    function getLastExecuteOrderId(address _market) public view returns (uint256 start, uint256 end){
        uint256 lastOrderId = IMarket(_market).orderID();
        start = IMarket(_market).lastExecutedOrderId();
        uint256 deltaNum = lastOrderId.sub(start);
        if (deltaNum > batchExecuteLimit) deltaNum = batchExecuteLimit;
        start = start.add(1);
        end = start.add(deltaNum);
    }

    /// @notice get the not execute order ids
    /// @param _market market address
    /// @param _taker taker address
    /// @return ids order ids
    function getNotExecuteOrderIds(address _market, address _taker) external view returns (uint256[] memory){
        uint256[] memory ids = new uint256[](EnumerableSet.length(notExecuteOrderIds[_taker][_market]));
        for (uint256 i = 0; i < EnumerableSet.length(notExecuteOrderIds[_taker][_market]); i++) {
            ids[i] = EnumerableSet.at(notExecuteOrderIds[_taker][_market], i);
        }
        return ids;
    }

    /// @notice get the margin asset of an market
    function getMarketMarginAsset(address _market) internal view returns (address){
        return IManager(manager).getMarketMarginAsset(_market);
    }

    /// @notice get the configured execution fee of an order
    function getExecuteOrderFee() internal view returns (uint256){
        return IManager(manager).executeOrderFee();
    }

    fallback() external payable {
    }
}

