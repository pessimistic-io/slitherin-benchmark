// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./SafeMath.sol";
import "./SafeCast.sol";
import "./SignedSafeMath.sol";
import "./IMarketLogic.sol";
import "./IMarket.sol";
import "./IManager.sol";
import "./IPool.sol";
import "./IMarketPriceFeed.sol";
import "./IFundingLogic.sol";

contract MarketLogic is IMarketLogic {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SignedSafeMath for int8;
    using SafeCast for int256;
    using SafeCast for uint256;

    uint256 constant RATE_PRECISION = 1e6;          // rate decimal 1e6
    uint256 constant PRICE_PRECISION = 1e10;        // price decimal 1e10
    uint256 constant AMOUNT_PRECISION = 1e20;       // amount decimal 1e20

    address manager;
    address marketPriceFeed;

    event UpdateMarketPriceFeed(address marketPriceFeed);

    constructor(address _manager) {
        require(_manager != address(0), "MarketLogic: manager is zero address");
        manager = _manager;
    }

    function updateMarketPriceFeed(address _marketPriceFeed) external {
        require(IManager(manager).checkController(msg.sender), "MarketLogic: !controller");
        require(_marketPriceFeed != address(0), "MarketLogic: marketPriceFeed is zero address");
        marketPriceFeed = _marketPriceFeed;
        emit UpdateMarketPriceFeed(_marketPriceFeed);
    }

    /// @notice temporary variables used by the trading process
    struct TradeInternalParams {
        MarketDataStructure.MarketConfig marketConfig;     // config of the market
        MarketDataStructure.PositionMode positionMode;     // position mode

        uint8 marketType;                   // market type
        address pool;

        uint256 orderValue;                 // order values
        uint256 deltaAmount;                // amount changes of the position during the order execution
        uint256 price;                      // trade price
        uint256 indexPrice;                 // index price when order execution
        uint256 closeRatio;                 // close ratio if reducing position

        uint256 settleTakerMargin;          // taker margin to be settled
        uint256 settleMakerMargin;          // maker(pool) margin to be settled
        uint256 settleValue;                // position value to be settled
        uint256 settleDebtShare;            // position debt shares to be settled
        uint256 interestPayment;            // interests amount to be settled

        uint256 feeAvailable;               // available trading fee, original trading fee subs the discount and invitor reward
        uint256 feeForOriginal;             // fee charged by increase or decrease original position
        uint256 feeForPositionReversal;     // fee charged by position reversal part
        uint256 feeToDiscountSettle;        // fee discount of the origin part
        int256 toTaker;                     // refund to the taker
    }

    /// @notice trade logic, calculate all things when an order is executed
    /// @param id order id
    /// @param positionId position id
    /// @param discountRate discount ratio of the trading fee
    /// @param inviteRate fee reward ratio for the invitor
    /// @return order order
    /// @return position position
    /// @return response response detailed in the data structure declaration
    /// @return errorCode errorCode {0: success, non-zero: fail}
    function trade(uint256 id, uint256 positionId, uint256 discountRate, uint256 inviteRate) external view override returns (MarketDataStructure.Order memory order, MarketDataStructure.Position memory position, MarketDataStructure.TradeResponse memory response, uint256 errorCode) {
        // init parameters and configurations to be used
        TradeInternalParams memory iParams;
        iParams.marketConfig = IMarket(msg.sender).getMarketConfig();
        iParams.marketType = IMarket(msg.sender).marketType();
        iParams.pool = IMarket(msg.sender).pool();
        order = IMarket(msg.sender).getOrder(id);
        iParams.positionMode = IMarket(msg.sender).positionModes(order.taker);
        position = IMarket(msg.sender).getPosition(positionId);

        if (order.id == 0 || order.status != MarketDataStructure.OrderStatus.Open) return (order, position, response, 2);

        // trigger condition validation
        if (order.triggerPrice > 0) {
            if (block.timestamp >= order.createTs.add(IManager(manager).triggerOrderDuration())) return (order, position, response, 4);
            iParams.indexPrice = getIndexPrice(msg.sender, order.direction == 1);
            // trigger direction: 1 indicates >=, -1 indicates <=
            if (order.triggerDirection == 1 ? iParams.indexPrice < order.triggerPrice : iParams.indexPrice > order.triggerPrice) return (order, position, response, 5);
            order.tradeIndexPrice = iParams.indexPrice;
        }

        // position initiation if empty
        if (position.amount == 0) {
            position.id = positionId;
            position.taker = order.taker;
            position.market = order.market;
            position.multiplier = order.multiplier;
            position.takerLeverage = order.takerLeverage;
            position.direction = order.direction;
            position.isETH = order.isETH;
            position.stopLossPrice = 0;
            position.takeProfitPrice = 0;
            position.lastTPSLTs = 0;
        } else {
            // ensure the same leverage in order and position if the position is not empty
            if (position.takerLeverage != order.takerLeverage) return (order, position, response, 6);
        }

        // get trading price, calculate delta amount and delta value
        if (order.orderType == MarketDataStructure.OrderType.Open || order.orderType == MarketDataStructure.OrderType.TriggerOpen) {
            iParams.orderValue = adjustPrecision(order.freezeMargin.mul(order.takerLeverage), iParams.marketConfig.marketAssetPrecision, AMOUNT_PRECISION);
            if (iParams.marketType == 0 || iParams.marketType == 2) {
                if (iParams.marketType == 2) {
                    iParams.orderValue = iParams.orderValue.mul(RATE_PRECISION).div(position.multiplier);
                }
                iParams.price = getPrice(order.market, iParams.orderValue, iParams.marketConfig.takerValueMax, order.direction == 1);
                if (iParams.price == 0) return (order, position, response, 1);

                iParams.deltaAmount = iParams.orderValue.mul(PRICE_PRECISION).div(iParams.price);
            } else {
                iParams.price = getPrice(order.market, iParams.orderValue, iParams.marketConfig.takerValueMax, order.direction == 1);
                if (iParams.price == 0) return (order, position, response, 1);

                iParams.deltaAmount = iParams.orderValue.mul(iParams.price).div(PRICE_PRECISION);
            }
        } else {
            if (position.amount == 0 || position.direction == order.direction) return (order, position, response, 7);
            iParams.deltaAmount = position.amount >= order.amount ? order.amount : position.amount;
            iParams.closeRatio = iParams.deltaAmount.mul(AMOUNT_PRECISION).div(position.amount);

            iParams.price = getPrice(order.market, position.value.mul(iParams.closeRatio).div(AMOUNT_PRECISION), iParams.marketConfig.takerValueMax, order.direction == 1);
            if (iParams.price == 0) return (order, position, response, 1);

            if (iParams.marketType == 0 || iParams.marketType == 2) {
                iParams.orderValue = iParams.deltaAmount.mul(iParams.price).div(PRICE_PRECISION);
            } else {
                iParams.orderValue = iParams.deltaAmount.mul(PRICE_PRECISION).div(iParams.price);
            }
        }

        if ((order.takerOpenPriceMin > 0 ? iParams.price < order.takerOpenPriceMin : false) ||
            (order.takerOpenPriceMax > 0 ? iParams.price > order.takerOpenPriceMax : false))
            return (order, position, response, 3);

        response.tradeValue = iParams.marketType == 1 ? iParams.deltaAmount : iParams.orderValue;

        order.takerFee = iParams.orderValue.mul(iParams.marketConfig.tradeFeeRate).div(RATE_PRECISION);
        if (iParams.marketType == 2) order.takerFee = order.takerFee.mul(position.multiplier).div(RATE_PRECISION);
        order.takerFee = adjustPrecision(order.takerFee, AMOUNT_PRECISION, iParams.marketConfig.marketAssetPrecision);

        order.feeToInviter = order.takerFee.mul(inviteRate).div(RATE_PRECISION);
        order.feeToDiscount = order.takerFee.mul(discountRate).div(RATE_PRECISION);

        iParams.feeAvailable = order.takerFee.sub(order.feeToInviter).sub(order.feeToDiscount);
        order.feeToMaker = iParams.feeAvailable.mul(iParams.marketConfig.makerFeeRate).div(RATE_PRECISION);
        order.feeToExchange = iParams.feeAvailable.sub(order.feeToMaker);

        if (position.direction == order.direction) {
            // increase position amount
            if (position.amount > 0) {
                errorCode = increasePositionValidate(iParams.price, iParams.pool, iParams.marketType, iParams.marketConfig.marketAssetPrecision, position);
                if (errorCode != 0) return (order, position, response, errorCode);
            }

            position.amount = position.amount.add(iParams.deltaAmount);
            position.value = position.value.add(iParams.orderValue);
            order.rlzPnl = 0;
            order.amount = iParams.deltaAmount;
            position.makerMargin = position.makerMargin.add(order.freezeMargin.mul(order.takerLeverage));
            position.takerMargin = position.takerMargin.add(order.freezeMargin.sub(order.takerFee).add(order.feeToDiscount));
            // interests global information updated before
            position.debtShare = position.debtShare.add(IPool(iParams.pool).getCurrentShare(position.direction, order.freezeMargin.mul(order.takerLeverage)));

            response.isIncreasePosition = true;
        } else {
            // decrease the position or position reversal
            if (iParams.closeRatio == 0) {
                iParams.closeRatio = iParams.deltaAmount.mul(AMOUNT_PRECISION).div(position.amount);
            }

            if (position.amount >= iParams.deltaAmount) {
                // decrease the position, no position reversal

                // split the position data according to the close ratio
                iParams.settleTakerMargin = position.takerMargin.mul(iParams.closeRatio).div(AMOUNT_PRECISION);
                iParams.settleMakerMargin = position.makerMargin.mul(iParams.closeRatio).div(AMOUNT_PRECISION);
                iParams.settleValue = position.value.mul(iParams.closeRatio).div(AMOUNT_PRECISION);
                iParams.settleDebtShare = position.debtShare.mul(iParams.closeRatio).div(AMOUNT_PRECISION);
                order.fundingPayment = position.fundingPayment.mul(iParams.closeRatio.toInt256()).div(AMOUNT_PRECISION.toInt256());

                // calculate the trading pnl, funding payment and interest payment
                order.rlzPnl = calculatePnl(iParams.orderValue, iParams.settleValue, iParams.marketType, iParams.marketConfig.marketAssetPrecision, position);
                order.interestPayment = getInterestPayment(iParams.pool, position.direction, position.debtShare, position.makerMargin);
                response.leftInterestPayment = order.interestPayment.mul(AMOUNT_PRECISION - iParams.closeRatio).div(AMOUNT_PRECISION);
                order.interestPayment = order.interestPayment.sub(response.leftInterestPayment);
                iParams.toTaker = iParams.settleTakerMargin.sub(order.takerFee).toInt256().sub(order.interestPayment.toInt256()).add(order.feeToDiscount.toInt256()).add(order.rlzPnl).sub(order.fundingPayment);

                // in case of bankruptcy
                if (iParams.toTaker < 0) return (order, position, response, 10);
                // rlzPnl - fundingPayment <= maker(pool) margin
                if (order.rlzPnl > iParams.settleMakerMargin.toInt256().add(order.fundingPayment)) return (order, position, response, 11);

                // update order and position data
                response.toTaker = iParams.toTaker.toUint256().add(order.freezeMargin);

                order.amount = iParams.deltaAmount;
                position.fundingPayment = position.fundingPayment.sub(order.fundingPayment);
                position.pnl = position.pnl.add(order.rlzPnl);
                position.takerMargin = position.takerMargin.sub(iParams.settleTakerMargin);
                position.makerMargin = position.makerMargin.sub(iParams.settleMakerMargin);
                position.debtShare = position.debtShare.sub(iParams.settleDebtShare);
                position.amount = position.amount.sub(iParams.deltaAmount);
                position.value = position.value.sub(iParams.settleValue);

                response.isDecreasePosition = true;
            }
            else {
                // position reversal, only allowed in the one-way position mode
                // which is equivalent to two separate processes: 1. fully close the position; 2. open a new with opposite direction;
                if (iParams.positionMode != MarketDataStructure.PositionMode.OneWay) return (order, position, response, 13);

                // split the order data according to the close ratio
                iParams.settleTakerMargin = order.freezeMargin.mul(AMOUNT_PRECISION).div(iParams.closeRatio);
                iParams.settleValue = iParams.orderValue.mul(AMOUNT_PRECISION).div(iParams.closeRatio);

                // calculate the trading pnl, funding payment and interest payment
                order.rlzPnl = calculatePnl(iParams.settleValue, position.value, iParams.marketType, iParams.marketConfig.marketAssetPrecision, position);

                // specially the trading fee will be split to tow parts
                iParams.feeToDiscountSettle = order.feeToDiscount.mul(AMOUNT_PRECISION).div(iParams.closeRatio);
                iParams.feeForOriginal = order.takerFee.mul(AMOUNT_PRECISION).div(iParams.closeRatio);
                iParams.feeForPositionReversal = order.takerFee.sub(iParams.feeForOriginal).sub(order.feeToDiscount.sub(iParams.feeToDiscountSettle));
                iParams.feeForOriginal = iParams.feeForOriginal.sub(iParams.feeToDiscountSettle);

                order.interestPayment = getInterestPayment(iParams.pool, position.direction, position.debtShare, position.makerMargin);
                iParams.toTaker = position.takerMargin.toInt256().sub(position.fundingPayment).sub(iParams.feeForOriginal.toInt256()).sub(order.interestPayment.toInt256()).add(order.rlzPnl);

                // in case of bankruptcy
                if (iParams.toTaker < 0) return (order, position, response, 14);
                // rlzPnl - fundingPayment <= maker(pool) margin
                if (order.rlzPnl > position.makerMargin.toInt256().add(position.fundingPayment)) return (order, position, response, 15);

                response.toTaker = iParams.toTaker.toUint256().add(iParams.settleTakerMargin);

                // update order and position data
                order.fundingPayment = position.fundingPayment;
                order.amount = position.amount;
                position.amount = iParams.deltaAmount.sub(position.amount);
                position.value = iParams.orderValue.sub(iParams.settleValue);
                position.direction = order.direction;
                position.takerMargin = order.freezeMargin.sub(iParams.settleTakerMargin);
                position.makerMargin = position.takerMargin.mul(order.takerLeverage);
                position.takerMargin = position.takerMargin.sub(iParams.feeForPositionReversal);
                position.fundingPayment = 0;
                position.pnl = position.pnl.add(order.rlzPnl);
                position.debtShare = IPool(iParams.pool).getCurrentShare(position.direction, position.makerMargin);
                position.stopLossPrice = 0;
                position.takeProfitPrice = 0;
                position.lastTPSLTs = 0;
                
                response.isDecreasePosition = true;
                response.isIncreasePosition = true;
            }
        }

        order.frX96 = IMarket(msg.sender).fundingGrowthGlobalX96();
        order.tradeTs = block.timestamp;
        order.tradePrice = iParams.price;
        order.status = MarketDataStructure.OrderStatus.Opened;
        position.lastUpdateTs = position.amount > 0 ? block.timestamp : 0;

        return (order, position, response, 0);
    }

    /// @notice calculation trading pnl using the position open value and closing order value
    /// @param  closeValue close order value
    /// @param  openValue position open value
    /// @param  marketType market type
    /// @param  marketAssetPrecision base asset precision of the market
    /// @param  position position data
    function calculatePnl(
        uint256 closeValue,
        uint256 openValue,
        uint8 marketType,
        uint256 marketAssetPrecision,
        MarketDataStructure.Position memory position
    ) internal pure returns (int256 rlzPnl){
        rlzPnl = closeValue.toInt256().sub(openValue.toInt256());
        if (marketType == 1) rlzPnl = rlzPnl.neg256();
        if (marketType == 2) rlzPnl = rlzPnl.mul(position.multiplier.toInt256()).div((RATE_PRECISION).toInt256());
        rlzPnl = rlzPnl.mul(position.direction);
        rlzPnl = rlzPnl.mul(marketAssetPrecision.toInt256()).div(AMOUNT_PRECISION.toInt256());
    }

    /// @notice validation when increase position, require the position is neither bankruptcy nor reaching the profit earn limit
    /// @param price trading price
    /// @param pool pool address
    /// @param marketType market type
    /// @param marketAssetPrecision precision of market base asset
    /// @param position position data
    /// @return uint256 0 if validate passed non-zero error
    function increasePositionValidate(
        uint256 price,
        address pool,
        uint8 marketType,
    //    uint256 discountRate,
    //    uint256 feeRate,
        uint256 marketAssetPrecision,
        MarketDataStructure.Position memory position
    ) internal view returns (uint256){
        uint256 closeValue;
        if (marketType == 0 || marketType == 2) {
            closeValue = position.amount.mul(price).div(PRICE_PRECISION);
        } else {
            closeValue = position.amount.mul(PRICE_PRECISION).div(price);
        }

        int256 pnl = calculatePnl(closeValue, position.value, marketType, marketAssetPrecision, position);
        uint256 interestPayment = getInterestPayment(pool, position.direction, position.debtShare, position.makerMargin);

        /*----
        uint256 fee = closeValue.mul(feeRate).div(RATE_PRECISION);
        if (marketType == 2) fee = fee.mul(position.multiplier).div(RATE_PRECISION);
        fee = adjustPrecision(fee, AMOUNT_PRECISION, marketAssetPrecision);
        fee = fee.sub(fee.mul(discountRate).div(RATE_PRECISION));
        if (pnl.neg256() > position.takerMargin.toInt256().sub(position.fundingPayment).sub(interestPayment.toInt256()).sub(fee.toInt256())) return 8;
        // ---- */

        // taker margin + pnl - fundingPayment - interestPayment > 0
        if (pnl.neg256() > position.takerMargin.toInt256().sub(position.fundingPayment).sub(interestPayment.toInt256())) return 8;
        // pnl - fundingPayment < maker(pool) margin
        if (pnl > position.makerMargin.toInt256().add(position.fundingPayment)) return 9;
        return 0;
    }

    struct LiquidateInfoInternalParams {
        MarketDataStructure.MarketConfig marketConfig;
        uint8 marketType;
        address pool;
        int256 remain;
        uint256 riskFund;
        int256 leftTakerMargin;
        int256 leftMakerMargin;
        uint256 closeValue;
    }

    /// @notice  calculate when position is liquidated, maximum profit stopped and tpsl closed by user setting
    /// @param params parameters, detailed in the data structure declaration
    /// @return response LiquidateInfoResponse
    function getLiquidateInfo(LiquidityInfoParams memory params) public view override returns (LiquidateInfoResponse memory response) {
        LiquidateInfoInternalParams memory iParams;
        iParams.marketConfig = IMarket(params.position.market).getMarketConfig();
        iParams.marketType = IMarket(params.position.market).marketType();
        iParams.pool = IMarket(params.position.market).pool();
        response.indexPrice = getIndexPrice(params.position.market, params.position.direction == - 1);

        //if Liquidate,trade fee is zero
        if (params.action == MarketDataStructure.OrderType.Liquidate || params.action == MarketDataStructure.OrderType.TakeProfit) {
            require(isLiquidateOrProfitMaximum(params.position, iParams.marketConfig.mm, response.indexPrice, iParams.marketConfig.marketAssetPrecision), "MarketLogic: position is not enough liquidity");
            response.price = IMarketPriceFeed(marketPriceFeed).priceForLiquidate(IMarket(params.position.market).token(), params.position.direction == - 1);
        } else {
            if (params.action == MarketDataStructure.OrderType.UserTakeProfit) {
                require(params.position.takeProfitPrice > 0 && (params.position.direction == 1 ? response.indexPrice >= params.position.takeProfitPrice : response.indexPrice <= params.position.takeProfitPrice), "MarketLogic:indexPrice does not match takeProfitPrice");
            } else if (params.action == MarketDataStructure.OrderType.UserStopLoss) {
                require(params.position.stopLossPrice > 0 && (params.position.direction == 1 ? response.indexPrice <= params.position.stopLossPrice : response.indexPrice >= params.position.stopLossPrice), "MarketLogic:indexPrice does not match stopLossPrice");
            } else {
                require(false, "MarketLogic:action error");
            }

            response.price = getPrice(params.position.market, params.position.value, iParams.marketConfig.takerValueMax, params.position.direction == - 1);
        }


        (response.pnl, iParams.closeValue) = getUnPNL(params.position, response.price, iParams.marketConfig.marketAssetPrecision);

        response.tradeValue = iParams.marketType == 1 ? params.position.amount : iParams.closeValue;

        if (params.action != MarketDataStructure.OrderType.Liquidate) {
            response.takerFee = adjustPrecision(iParams.closeValue.mul(iParams.marketConfig.tradeFeeRate).div(RATE_PRECISION), AMOUNT_PRECISION, iParams.marketConfig.marketAssetPrecision);
            response.feeToDiscount = response.takerFee.mul(params.discountRate).div(RATE_PRECISION);
            response.feeToInviter = response.takerFee.mul(params.inviteRate).div(RATE_PRECISION);
            response.feeToMaker = response.takerFee.sub(response.feeToDiscount).sub(response.feeToInviter).mul(iParams.marketConfig.makerFeeRate).div(RATE_PRECISION);
            response.feeToExchange = response.takerFee.sub(response.feeToInviter).sub(response.feeToDiscount).sub(response.feeToMaker);
        }

        //calc close position interests payment
        response.payInterest = getInterestPayment(iParams.pool, params.position.direction, params.position.debtShare, params.position.makerMargin);

        // adjust pnl if bankruptcy occurred on either user side or maker(pool) side
        iParams.leftTakerMargin = params.position.takerMargin.toInt256().sub(params.position.fundingPayment).sub(response.takerFee.toInt256()).add(response.feeToDiscount.toInt256()).sub(response.payInterest.toInt256());
        if (iParams.leftTakerMargin.add(response.pnl) < 0) {
            response.pnl = iParams.leftTakerMargin.neg256();
        }

        iParams.leftMakerMargin = params.position.makerMargin.toInt256().add(params.position.fundingPayment);
        if (iParams.leftMakerMargin.sub(response.pnl) < 0) {
            response.pnl = iParams.leftMakerMargin;
        }

        //if Liquidate,should calc riskFunding
        if (params.action == MarketDataStructure.OrderType.Liquidate) {
            iParams.remain = iParams.leftTakerMargin.add(response.pnl);
            if (iParams.remain > 0) {
                iParams.riskFund = adjustPrecision(params.position.value.mul(iParams.marketConfig.liquidateRate).div(RATE_PRECISION), AMOUNT_PRECISION, iParams.marketConfig.marketAssetPrecision);
                if (iParams.remain > iParams.riskFund.toInt256()) {
                    response.toTaker = iParams.remain.sub(iParams.riskFund.toInt256()).toUint256();
                    response.riskFunding = iParams.riskFund;
                } else {
                    response.toTaker = 0;
                    response.riskFunding = iParams.remain.toUint256();
                }
            }
        } else {
            response.toTaker = iParams.leftTakerMargin.add(response.pnl).toUint256();
        }

        return response;
    }

    struct InternalParams {
        int256 pnl;
        uint256 currentValue;
        uint256 payInterest;
        bool isTakerLiq;
        bool isMakerBroke;
    }

    /// @notice check if the position should be liquidated or reaches the maximum profit
    /// @param  position position info
    function isLiquidateOrProfitMaximum(MarketDataStructure.Position memory position, uint256 mm, uint256 indexPrice, uint256 toPrecision) public view override returns (bool) {
        InternalParams memory params;
        //calc position unrealized pnl
        (params.pnl, params.currentValue) = getUnPNL(position, indexPrice, toPrecision);
        //calc position current payInterest
        params.payInterest = getInterestPayment(IMarket(position.market).pool(), position.direction, position.debtShare, position.makerMargin);

        //if takerMargin - fundingPayment + pnl - payInterest <= currentValue * mm,position is liquidity
        params.isTakerLiq = position.takerMargin.toInt256().sub(position.fundingPayment).add(params.pnl).sub(params.payInterest.toInt256()) <= params.currentValue.mul(mm).mul(toPrecision).div(RATE_PRECISION).div(AMOUNT_PRECISION).toInt256();
        //if pnl - fundingPayment >= makerMargin,position is liquidity
        params.isMakerBroke = params.pnl.sub(position.fundingPayment) >= position.makerMargin.toInt256();

        return params.isTakerLiq || params.isMakerBroke;
    }

    /// @notice calculate position unPnl
    /// @param position position data
    /// @param price trading price
    /// @param toPrecision result precision
    /// @return pnl
    /// @return currentValue close value by price
    function getUnPNL(MarketDataStructure.Position memory position, uint256 price, uint256 toPrecision) public view returns (int256 pnl, uint256 currentValue){
        uint8 marketType = IMarket(position.market).marketType();

        if (marketType == 0 || marketType == 2) {
            currentValue = price.mul(position.amount).div(PRICE_PRECISION);
            pnl = currentValue.toInt256().sub(position.value.toInt256());
            if (marketType == 2) {
                pnl = pnl.mul(position.multiplier.toInt256()).div(RATE_PRECISION.toInt256());
                currentValue = currentValue.mul(position.multiplier).div(RATE_PRECISION);
            }
        } else {
            currentValue = position.amount.mul(PRICE_PRECISION).div(price);
            pnl = position.value.toInt256().sub(currentValue.toInt256());
        }

        pnl = pnl.mul(position.direction).mul(toPrecision.toInt256()).div(AMOUNT_PRECISION.toInt256());
    }

    /// @notice calculate the maximum position margin can be removed out
    /// @param position position data
    /// @return maxDecreaseMargin
    function getMaxTakerDecreaseMargin(MarketDataStructure.Position memory position) external view override returns (uint256 maxDecreaseMargin) {
        MarketDataStructure.MarketConfig memory marketConfig = IMarket(position.market).getMarketConfig();
        address fundingLogic = IMarket(position.market).getLogicAddress();
        position.frLastX96 = IFundingLogic(fundingLogic).getFunding(position.market);
        position.fundingPayment = position.fundingPayment.add(IFundingLogic(fundingLogic).getFundingPayment(position.market, position.id, position.frLastX96));
        uint256 payInterest = getInterestPayment(IMarket(position.market).pool(), position.direction, position.debtShare, position.makerMargin);
        (int256 pnl,) = getUnPNL(position, getIndexPrice(position.market, position.direction == 1), marketConfig.marketAssetPrecision);
        uint256 minIM = adjustPrecision(position.value.mul(marketConfig.dMMultiplier).div(marketConfig.takerLeverageMax), AMOUNT_PRECISION, marketConfig.marketAssetPrecision);
        int256 profitAndFundingAndInterest = pnl.sub(payInterest.toInt256()).sub(position.fundingPayment);
        int256 maxDecreaseMarginLimit = position.takerMargin.toInt256().sub(marketConfig.takerMarginMin.toInt256());
        int256 maxDecrease = position.takerMargin.toInt256().add(profitAndFundingAndInterest > 0 ? 0 : profitAndFundingAndInterest).sub(minIM.toInt256());
        if (maxDecreaseMarginLimit > 0 && maxDecrease > 0) {
            maxDecreaseMargin = maxDecreaseMarginLimit > maxDecrease ? maxDecrease.toUint256() : maxDecreaseMarginLimit.toUint256();
        } else {
            maxDecreaseMargin = 0;
        }
    }

    /// @notice create a new order
    /// @param params CreateParams
    /// @return order
    function createOrderInternal(MarketDataStructure.CreateInternalParams memory params) external view override returns (MarketDataStructure.Order memory order){
        address market = msg.sender;
        MarketDataStructure.MarketConfig memory marketConfig = IMarket(market).getMarketConfig();
        MarketDataStructure.PositionMode positionMode = IMarket(market).positionModes(params._taker);

        order.isETH = params.isETH;
        order.status = MarketDataStructure.OrderStatus.Open;
        order.market = market;
        order.taker = params._taker;
        order.multiplier = marketConfig.multiplier;
        order.takerOpenPriceMin = params.minPrice;
        order.takerOpenPriceMax = params.maxPrice;
        order.triggerPrice = marketConfig.createTriggerOrderPaused ? 0 : params.triggerPrice;
        order.triggerDirection = marketConfig.createTriggerOrderPaused ? int8(0) : params.triggerDirection;
        order.createTs = block.timestamp;
        order.mode = positionMode;

        //get position id by direction an orderType
        uint256 positionId = params.reduceOnly == 0 ? IMarket(market).getPositionId(params._taker, params.direction) : params.id;
        MarketDataStructure.Position memory position = IMarket(market).getPosition(positionId);

        if (params.reduceOnly == 1) {
            require(params.id != 0, "MarketLogic:id error");
            require(position.taker == params._taker, "MarketLogic: position not belong to taker");
            require(position.amount > 0, "MarketLogic: amount error");
            order.takerLeverage = position.takerLeverage;
            order.direction = position.direction.neg256().toInt8();
            order.amount = params.amount;
            order.isETH = position.isETH;
            // only under the hedging position model reduce only orders are allowed to be trigger orders
            if (positionMode == MarketDataStructure.PositionMode.OneWay) {
                order.triggerPrice = 0;
                order.triggerDirection = 0;
            }
            order.orderType = order.triggerPrice > 0 ? MarketDataStructure.OrderType.TriggerClose : MarketDataStructure.OrderType.Close;
        } else {
            //open orders or trigger open orders
            uint256 value = adjustPrecision(params.margin.mul(params.leverage), marketConfig.marketAssetPrecision, AMOUNT_PRECISION);
            require(params.direction == 1 || params.direction == - 1, "MarketLogic: direction error");
            require(marketConfig.takerLeverageMin <= params.leverage && params.leverage <= marketConfig.takerLeverageMax, "MarketLogic: leverage not allow");
            require(marketConfig.takerMarginMin <= params.margin && params.margin <= marketConfig.takerMarginMax, "MarketLogic: margin not allow");
            require(marketConfig.takerValueMin <= value && value <= marketConfig.takerValueMax, "MarketLogic: value not allow");
            require(position.amount > 0 ? position.takerLeverage == params.leverage : true, "MarketLogic: leverage error");
            order.isETH = params.isETH;
            order.direction = params.direction;
            order.takerLeverage = params.leverage;
            order.freezeMargin = params.margin;
            order.orderType = order.triggerPrice > 0 ? MarketDataStructure.OrderType.TriggerOpen : MarketDataStructure.OrderType.Open;
        }

        if (params.isLiquidate) {
            order.orderType = MarketDataStructure.OrderType.Liquidate;
            order.executeFee = 0;
        } else {
            order.executeFee = IManager(manager).executeOrderFee();
        }
        
        return order;
    }

    /// @notice check order params
    /// @param id order id
    function checkOrder(uint256 id) external view override {
        address market = msg.sender;
        MarketDataStructure.Order memory order = IMarket(market).getOrder(id);
        MarketDataStructure.MarketConfig memory marketConfig = IMarket(market).getMarketConfig();
        //if open or trigger open ,should be check taker value limit
        if (order.orderType == MarketDataStructure.OrderType.Open || order.orderType == MarketDataStructure.OrderType.TriggerOpen) {
            int256 orderValue = IMarket(market).takerOrderTotalValues(order.taker, order.direction);
            require(orderValue <= marketConfig.takerValueLimit, "MarketLogic: total value of unexecuted orders exceeded limits");
            MarketDataStructure.Position memory position = IMarket(market).getPosition(IMarket(market).getPositionId(order.taker, order.direction));
            if (order.direction == position.direction) {
                require(position.value.toInt256().add(orderValue) <= marketConfig.takerValueLimit, "MarketLogic: total value of unexecuted orders exceeded limits");
            }
        }

        if (order.triggerPrice > 0) require(order.triggerDirection == 1 || order.triggerDirection == - 1, "MarketLogic:trigger direction error");
        require(IMarket(market).takerOrderNum(order.taker, order.orderType) <= IManager(manager).orderNumLimit(), "MarketLogic: number of unexecuted orders exceed limit");
    }

    /// @notice check if users are available to change the position mode
    ///         users are allowed to change position mode only under the situation that there's no any type of order and no position under the market.
    /// @param _taker taker address
    /// @param _mode margin mode
    function checkSwitchMode(address _market, address _taker, MarketDataStructure.PositionMode _mode) public view override {
        MarketDataStructure.PositionMode positionMode = IMarket(_market).positionModes(_taker);
        require(positionMode != _mode, "MarketLogic: mode not change");
        require(
            getOrderNum(_market, _taker, MarketDataStructure.OrderType.Open) == 0 &&
            getOrderNum(_market, _taker, MarketDataStructure.OrderType.TriggerOpen) == 0 &&
            getOrderNum(_market, _taker, MarketDataStructure.OrderType.Close) == 0 &&
            getOrderNum(_market, _taker, MarketDataStructure.OrderType.TriggerClose) == 0,
            "MarketLogic: change position mode with orders"
        );
        require(
            getPositionAmount(_market, _taker, - 1) == 0 && getPositionAmount(_market, _taker, 1) == 0,
            "MarketLogic: change position mode with none-zero position"
        );
    }

    /// @notice validate market config params
    /// @param market market address
    /// @param _config market config
    function checkoutConfig(address market, MarketDataStructure.MarketConfig memory _config) external view override {
        uint256 marketType = IMarket(market).marketType();
        require(_config.makerFeeRate < RATE_PRECISION, "MarketLogic:fee percent error");
        require(_config.tradeFeeRate < RATE_PRECISION, "MarketLogic:feeRate more than one");
        require(marketType == 2 ? _config.multiplier > 0 : true, "MarketLogic:ratio error");
        require(_config.takerLeverageMin > 0 && _config.takerLeverageMin < _config.takerLeverageMax, "MarketLogic:leverage error");
        require(_config.mm > 0 && _config.mm < RATE_PRECISION.div(_config.takerLeverageMax), "MarketLogic:mm error");
        require(_config.takerMarginMin > 0 && _config.takerMarginMin < _config.takerMarginMax, "MarketLogic:margin error");
        require(_config.takerValueMin > 0 && _config.takerValueMin < _config.takerValueMax, "MarketLogic:value error");
    }

    /// @notice calculation position interest
    /// @param  pool pool address
    /// @param  direction position direction
    /// @param  debtShare debt share amount
    /// @param  makerMargin maker(pool) margin
    /// @return uint256 interest
    function getInterestPayment(address pool, int8 direction, uint256 debtShare, uint256 makerMargin) internal view returns (uint256){
        uint256 borrowAmount = IPool(pool).getCurrentAmount(direction, debtShare);
        return borrowAmount < makerMargin ? 0 : borrowAmount.sub(makerMargin);
    }

    function getOrderNum(address _market, address _taker, MarketDataStructure.OrderType orderType) internal view returns (uint256){
        return IMarket(_market).takerOrderNum(_taker, orderType);
    }

    function getPositionAmount(address _market, address _taker, int8 direction) internal view returns (uint256){
        return IMarket(_market).getPosition(IMarket(_market).getPositionId(_taker, direction)).amount;
    }

    /// @notice get trading price
    /// @param _market market address
    /// @param value trading value
    /// @param maxValue trading value maximum limit in one single open order
    /// @return price
    function getPrice(address _market, uint256 value, uint256 maxValue, bool _maximise) public view returns (uint256){
        return IMarketPriceFeed(marketPriceFeed).priceForTrade(IMarket(_market).token(), value, maxValue, _maximise);
    }

    function getIndexPrice(address _market, bool _maximise) public view returns (uint256){
        return IMarketPriceFeed(marketPriceFeed).priceForIndex(IMarket(_market).token(), _maximise);
    }

    /// @notice precision conversion
    /// @param _value value
    /// @param _from original precision
    /// @param _to target precision
    function adjustPrecision(uint256 _value, uint256 _from, uint256 _to) internal pure returns (uint256){
        return _value.mul(_to).div(_from);
    }
}

