// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./SafeCast.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";
import "./MarketDataStructure.sol";
import "./IPool.sol";
import "./IMarket.sol";
import "./IFundingLogic.sol";
import "./IManager.sol";
import "./IMarketLogic.sol";
import "./IMarketPriceFeed.sol";
import "./IMarketLogic.sol";
import "./PoolStorage.sol";

contract Periphery {
    using SignedSafeMath for int256;
    using SignedSafeMath for int8;
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    struct MarketInfo {
        address market;
        address pool;
        address token;
        address marginAsset;
        uint8 marketType;
        MarketDataStructure.MarketConfig marketConfig;
    }

    struct PoolInfo {
        uint256 minAddLiquidityAmount;
        uint256 minRemoveLiquidityAmount;
        uint256 reserveRate;
        uint256 removeLiquidityFeeRate;
        uint256 balance;
        uint256 sharePrice;
        uint256 assetAmount;
        bool addPaused;
        bool removePaused;
        uint256 totalSupply;
    }

    // rate decimal 1e6

    int256 public constant RATE_PRECISION = 1e6;
    // amount decimal 1e20
    uint256 public constant AMOUNT_PRECISION = 1e20;

    address public manager;
    address public marketPriceFeed;

    event UpdateMarketPriceFeed(address priceFeed);

    constructor(address _manager, address _marketPriceFeed) {
        require(_manager != address(0), "Periphery: _manager is the zero address");
        require(_marketPriceFeed != address(0), "Periphery: _marketPriceFeed is the zero address");
        manager = _manager;
        marketPriceFeed = _marketPriceFeed;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "Periphery: Must be controller");
        _;
    }

    function updateMarketPriceFeed(address _marketPriceFeed) external onlyController {
        require(_marketPriceFeed != address(0), "Periphery: _marketPriceFeed is the zero address");
        marketPriceFeed = _marketPriceFeed;
        emit UpdateMarketPriceFeed(_marketPriceFeed);
    }

    ///below are view functions
    function getAllMarkets() public view returns (MarketInfo[] memory) {
        address[]  memory markets = IManager(manager).getAllMarkets();
        MarketInfo[] memory infos = new MarketInfo[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            MarketInfo memory info;
            info.market = markets[i];
            info.pool = IMarket(markets[i]).pool();
            info.marginAsset = IManager(manager).getMarketMarginAsset(markets[i]);
            info.marketType = IMarket(markets[i]).marketType();
            info.marketConfig = IMarket(markets[i]).getMarketConfig();
            infos[i] = info;
        }
        return infos;
    }

    function getAllPools() external view returns (address[] memory) {
        return IManager(manager).getAllPools();
    }

    function getPoolInfo(address _pool) external view returns (PoolInfo memory info){
        info.minAddLiquidityAmount = IPool(_pool).minAddLiquidityAmount();
        info.minRemoveLiquidityAmount = IPool(_pool).minRemoveLiquidityAmount();
        info.reserveRate = IPool(_pool).reserveRate();
        info.removeLiquidityFeeRate = IPool(_pool).removeLiquidityFeeRate();
        (info.sharePrice, info.balance) = IPool(_pool).getSharePrice();
        info.assetAmount = IPool(_pool).getAssetAmount();
        info.addPaused = IPool(_pool).addPaused();
        info.removePaused = IPool(_pool).removePaused();
        info.totalSupply = IPool(_pool).totalSupply();
    }

    function getOrderIds(address _market, address taker) external view returns (uint256[] memory) {
        return IMarket(_market).getOrderIds(taker);
    }

    function getOrder(address _market, uint256 id) public view returns (MarketDataStructure.Order memory) {
        return IMarket(_market).getOrder(id);
    }

    function getPositionId(address _market, address _taker, int8 _direction) public view returns (uint256) {
        uint256 id = IMarket(_market).getPositionId(_taker, _direction);
        return id;
    }

    function getPosition(address _market, uint256 _id) public view returns (MarketDataStructure.Position memory _position, int256 _fundingPayment, uint256 _interestPayment, uint256 _maxDecreaseMargin) {
        (_position) = IMarket(_market).getPosition(_id);
        (, _fundingPayment) = getPositionFundingPayment(_market, _position.id);
        (_interestPayment) = getPositionInterestPayment(_market, _position.id);
        (_maxDecreaseMargin) = getMaxDecreaseMargin(_market, _position.id);
    }

    ///@notice get all positions of a taker, if _market is 0, get all positions of the taker
    ///@param _market the market address
    ///@param _taker the taker address
    ///@return positions the positions of the taker
    function getAllPosition(address _market, address _taker) external view returns (MarketDataStructure.Position[] memory) {
        address[] memory markets;

        if (_market != address(0)) {
            markets = new address[](1);
            markets[0] = _market;
        } else {
            markets = IManager(manager).getAllMarkets();
        }

        MarketDataStructure.Position[] memory positions = new MarketDataStructure.Position[](markets.length * 2);
        uint256 index;
        for (uint256 i = 0; i < markets.length; i++) {
            uint256 longPositionId = getPositionId(markets[i], _taker, 1);
            MarketDataStructure.Position memory longPosition = IMarket(_market).getPosition(longPositionId);
            if (longPosition.amount > 0) {
                positions[index] = longPosition;
                index++;
            }

            uint256 shortPositionId = getPositionId(markets[i], _taker, - 1);
            if (longPositionId == shortPositionId) continue;
            MarketDataStructure.Position memory shortPosition = IMarket(_market).getPosition(shortPositionId);
            if (shortPosition.amount > 0) {
                positions[index] = shortPosition;
                index++;
            }
        }
        return positions;
    }

    function getPositionStatus(address _market, uint256 _id) external view returns (bool) {
        MarketDataStructure.Position memory position = IMarket(_market).getPosition(_id);
        if (position.amount > 0) {
            (address fundingLogic) = IMarket(_market).getLogicAddress();
            MarketDataStructure.MarketConfig memory marketConfig = IMarket(_market).getMarketConfig();
            uint256 indexPrice = IMarketPriceFeed(marketPriceFeed).priceForIndex(IMarket(_market).token(), position.direction == - 1);
            int256 frX96 = IFundingLogic(fundingLogic).getFunding(position.market);
            position.fundingPayment = position.fundingPayment.add(IFundingLogic(fundingLogic).getFundingPayment(_market, _id, frX96));
            return IMarketLogic(IMarket(_market).marketLogic()).isLiquidateOrProfitMaximum(position, marketConfig.mm, indexPrice, marketConfig.marketAssetPrecision);
        }
        return false;
    }

    /// @notice get ids of maker's liquidity order
    /// @param _pool the pool where the order in
    /// @param _maker the address of taker
    function getMakerOrderIds(address _pool, address _maker) external view returns (uint256[] memory _orderIds){
        (_orderIds) = IPool(_pool).getMakerOrderIds(_maker);
    }

    /// @notice get order by pool and order id
    /// @param _pool the pool where the order in
    /// @param _id the id of the order to get
    /// @return order
    function getPoolOrder(address _pool, uint256 _id) external view returns (PoolDataStructure.MakerOrder memory order){
        return IPool(_pool).getOrder(_id);
    }

    /// @notice get amount of lp by pool and taker
    /// @param _pool the pool where the liquidity in
    /// @param _maker the address of taker
    function getLpBalanceOf(address _pool, address _maker) external view returns (uint256 _liquidity, uint256 _totalSupply){
        (_liquidity, _totalSupply) = IPool(_pool).getLpBalanceOf(_maker);
    }

    /// @notice check can open or not
    /// @param _pool the pool to open
    /// @param _makerMargin margin amount
    /// @return result
    function canOpen(address _pool, address _market, uint256 _makerMargin) external view returns (bool){
        return IPool(_pool).canOpen(_market, _makerMargin);
    }

    /// @notice can remove liquidity or not
    /// @param _pool the pool to remove liquidity
    /// @param _liquidity the amount to remove liquidity
    function canRemoveLiquidity(address _pool, uint256 _liquidity) external view returns (bool){
        uint256 totalSupply = IPool(_pool).totalSupply();
        (,uint256 balance) = IPool(_pool).getSharePrice();
        if (totalSupply > 0) {
            (PoolStorage.DataByMarket memory allMarketPos, uint256 allMakerFreeze) = IPool(_pool).getAllMarketData();
            int256 totalUnPNL = IPool(_pool).makerProfitForLiquidity(false);
            if (totalUnPNL <= int256(allMarketPos.takerTotalMargin) && totalUnPNL * (- 1) <= int256(allMakerFreeze)) {
                uint256 amount = _liquidity.mul(allMakerFreeze.toInt256().add(balance.toInt256()).add(totalUnPNL).add(allMarketPos.makerFundingPayment).toUint256()).div(totalSupply);
                if (balance >= amount) {
                    return true;
                }
            }
        }
        return false;
    }


    /// @notice can add liquidity or not
    /// @param _pool the pool to add liquidity or not
    function canAddLiquidity(address _pool) external view returns (bool){
        (PoolStorage.DataByMarket memory allMarketPos, uint256 allMakerFreeze) = IPool(_pool).getAllMarketData();
        int256 totalUnPNL = IPool(_pool).makerProfitForLiquidity(true);
        if (totalUnPNL <= int256(allMarketPos.takerTotalMargin) && totalUnPNL.neg256() <= int256(allMakerFreeze)) {
            return true;
        }
        return false;
    }

    /// @notice get funding info
    /// @param id position id
    /// @param market the market address
    /// @return frX96 current funding rate
    /// @return fundingPayment funding payment
    function getPositionFundingPayment(address market, uint256 id) public view returns (int256 frX96, int256 fundingPayment){
        MarketDataStructure.Position memory position = IMarket(market).getPosition(id);
        (address calc) = IMarket(market).getLogicAddress();
        frX96 = IFundingLogic(calc).getFunding(market);
        fundingPayment = position.fundingPayment.add(IFundingLogic(calc).getFundingPayment(market, position.id, frX96));
    }

    function getPositionInterestPayment(address market, uint256 positionId) public view returns (uint256 positionInterestPayment){
        MarketDataStructure.Position memory position = IMarket(market).getPosition(positionId);
        address pool = IManager(manager).getMakerByMarket(market);
        uint256 amount = IPool(pool).getCurrentAmount(position.direction, position.debtShare);
        positionInterestPayment = amount < position.makerMargin ? 0 : amount - position.makerMargin;
    }

    function getFundingInfo(address market) external view returns (int256 frX96, int256 fgX96, uint256 lastUpdateTs){
        lastUpdateTs = IMarket(market).lastFrX96Ts();
        fgX96 = IMarket(market).fundingGrowthGlobalX96();
        (address calc) = IMarket(market).getLogicAddress();
        frX96 = IFundingLogic(calc).getFunding(market);
    }

    /// @notice get funding and interest info
    /// @param market the market address
    /// @return longBorrowRate one hour per ，scaled by 1e27
    /// @return longBorrowIG current ig
    /// @return shortBorrowRate one hour per ，scaled by 1e27
    /// @return shortBorrowIG current ig
    /// @return frX96 current fr
    /// @return fgX96 last fr
    /// @return lastUpdateTs last update time
    function getFundingAndInterestInfo(address market) public view returns (uint256 longBorrowRate, uint256 longBorrowIG, uint256 shortBorrowRate, uint256 shortBorrowIG, int256 frX96, int256 fgX96, uint256 lastUpdateTs){
        lastUpdateTs = IMarket(market).lastFrX96Ts();
        fgX96 = IMarket(market).fundingGrowthGlobalX96();
        (address calc) = IMarket(market).getLogicAddress();
        frX96 = IFundingLogic(calc).getFunding(market);

        address pool = IManager(manager).getMakerByMarket(market);
        (longBorrowRate, longBorrowIG) = IPool(pool).getCurrentBorrowIG(1);
        (shortBorrowRate, shortBorrowIG) = IPool(pool).getCurrentBorrowIG(- 1);
    }

    /// @notice get order id info
    /// @param market the market address
    /// @return orderID last order id
    /// @return lastExecutedOrderId last executed order id
    /// @return triggerOrderID last trigger order id
    function getMarketOrderIdInfo(address market) external view returns (uint256 orderID, uint256 lastExecutedOrderId, uint256 triggerOrderID){
        orderID = IMarket(market).orderID();
        lastExecutedOrderId = IMarket(market).lastExecutedOrderId();
        triggerOrderID = IMarket(market).triggerOrderID();
    }

    function getPositionMode(address _market, address _taker) external view returns (MarketDataStructure.PositionMode _mode){
        return IMarket(_market).positionModes(_taker);
    }

    function getMaxDecreaseMargin(address market, uint256 positionId) public view returns (uint256){
        return IMarketLogic(IMarket(market).marketLogic()).getMaxTakerDecreaseMargin(IMarket(market).getPosition(positionId));
    }

    function getOrderNumLimit(address _market, address _taker) external view returns (uint256 _currentOpenNum, uint256 _currentCloseNum, uint256 _currentTriggerOpenNum, uint256 _currentTriggerCloseNum, uint256 _limit){
        _currentOpenNum = IMarket(_market).takerOrderNum(_taker, MarketDataStructure.OrderType.Open);
        _currentCloseNum = IMarket(_market).takerOrderNum(_taker, MarketDataStructure.OrderType.Close);
        _currentTriggerOpenNum = IMarket(_market).takerOrderNum(_taker, MarketDataStructure.OrderType.TriggerOpen);
        _currentTriggerCloseNum = IMarket(_market).takerOrderNum(_taker, MarketDataStructure.OrderType.TriggerClose);
        _limit = IManager(manager).orderNumLimit();
    }

    /// @notice get position's liq price
    /// @param positionId position id
    ///@return liqPrice liquidation price,price is scaled by 1e8
    function getPositionLiqPrice(address market, uint256 positionId) external view returns (uint256 liqPrice){
        MarketDataStructure.MarketConfig memory marketConfig = IMarket(market).getMarketConfig();
        uint8 marketType = IMarket(market).marketType();

        MarketDataStructure.Position memory position = IMarket(market).getPosition(positionId);
        if (position.amount == 0) return 0;
        //calc position current payInterest
        uint256 payInterest = IPool(IMarket(market).pool()).getCurrentAmount(position.direction, position.debtShare).sub(position.makerMargin);
        //calc position current fundingPayment
        (, position.fundingPayment) = getPositionFundingPayment(position.market, positionId);
        int256 numerator;
        int256 denominator;
        int256 value = position.value.mul(marketConfig.marketAssetPrecision).div(AMOUNT_PRECISION).toInt256();
        int256 amount = position.amount.mul(marketConfig.marketAssetPrecision).div(AMOUNT_PRECISION).toInt256();
        if (marketType == 0) {
            numerator = position.fundingPayment.add(payInterest.toInt256()).add(value.mul(position.direction)).sub(position.takerMargin.toInt256()).mul(RATE_PRECISION);
            denominator = RATE_PRECISION.mul(position.direction).sub(marketConfig.mm.toInt256()).mul(amount);
        } else if (marketType == 1) {
            numerator = marketConfig.mm.toInt256().add(position.direction.mul(RATE_PRECISION)).mul(amount);
            denominator = position.takerMargin.toInt256().sub(position.fundingPayment).sub(payInterest.toInt256()).add(value.mul(position.direction)).mul(RATE_PRECISION);
        } else {
            numerator = position.fundingPayment.add(payInterest.toInt256()).sub(position.takerMargin.toInt256()).mul(RATE_PRECISION).add(value.mul(position.multiplier.toInt256()).mul(position.direction)).mul(RATE_PRECISION);
            denominator = RATE_PRECISION.mul(position.direction).sub(marketConfig.mm.toInt256()).mul(amount).mul(position.multiplier.toInt256());
        }

        if (denominator == 0) return 0;

        liqPrice = numerator.mul(1e8).div(denominator).toUint256();
    }
}

