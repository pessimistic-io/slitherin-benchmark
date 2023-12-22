// SPDX-License-Identifier: MIT
import "./Initializable.sol";
import "./SafeERC20.sol";

import "./IStorageT.sol";
import "./IPEXPairInfos.sol";
import "./INftRewards.sol";

pragma solidity 0.8.17;

contract PEXTradingCallbacksV1 is Initializable {
    using SafeERC20 for IERC20;

    // Contracts (constant)
    IStorageT public storageT;
    INftRewards public nftRewards;
    IPEXPairInfos public pairInfos;

    // Params (constant)
    uint constant PRECISION = 1e10;  // 10 decimals

    // Params (adjustable)
    uint public usdtVaultFeeP;  // % of closing fee going to USDT vault (eg. 40)
    uint public lpFeeP;        // % of closing fee going to PEX/USDT LPs (eg. 20)
    uint public sssFeeP;       // % of closing fee going to PEX staking (eg. 40)

    // State
    bool public isPaused;  // Prevent opening new trades
    bool public isDone;    // Prevent any interaction with the contract

    uint public MAX_SL_P;     // -75% PNL
    uint public MIN_SL_P;
    uint public MAX_GAIN_P;  // 900% PnL (10x)
    uint public MIN_GAIN_P;

    // Custom data types
    struct AggregatorAnswer{
        uint orderId;
        uint price;
        uint spreadP;
    }

    // Useful to avoid stack too deep errors
    struct Values{
        uint posUsdt; 
        uint levPosUsdt; 
        int profitP; 
        uint price;
        uint liqPrice;
        uint usdtSentToTrader;
        uint reward1;
        uint reward2;
        uint reward3;
    }

    struct Fees{
        uint rolloverFee;
        int fundingFee;
        uint closingFee;
    }

    // Events
    event MarketExecuted(
        uint indexed orderId,
        address indexed trader,
        IStorageT.Trade t,
        bool open,
        uint price,
        uint priceImpactP,
        uint positionSizeUsdt,
        int percentProfit,
        uint usdtSentToTrader,
        uint rolloverFee,
        int fundingFee,
        uint fee
    );

    event LimitExecuted(
        uint indexed orderId,
        address indexed trader,
        uint limitIndex,
        IStorageT.Trade t,
        address indexed nftHolder,
        IStorageT.LimitOrder orderType,
        uint price,
        uint priceImpactP,
        uint positionSizeUsdt,
        int percentProfit,
        uint usdtSentToTrader,
        uint rolloverFee,
        int fundingFee,
        uint fee
    );

    event MarketOpenCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex
    );
    event MarketCloseCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    event SlUpdated(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newSl
    );
    event SlCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    event ClosingFeeSharesPUpdated(
        uint usdtVaultFeeP,
        uint lpFeeP,
        uint sssFeeP
    );
    
    event Pause(bool paused);
    event Done(bool done);

    event DevGovFeeCharged(address indexed trader, uint valueUsdt);
    event ClosingRolloverFeeCharged(address indexed trader, uint valueUsdt);

    event AddressUpdated(string name, address a);

    event SLTPParamsUpdaated(uint maxSL, uint minSL, uint maxTP, uint minTP);

    function initialize(
        IStorageT _storageT,
        INftRewards _nftRewards,
        IPEXPairInfos _pairInfos,
        address vaultToApprove,
        uint _usdtVaultFeeP,
        uint _lpFeeP,
        uint _sssFeeP,
        uint _max_sl_p,
        uint _min_sl_p,
        uint _max_gain_p,
        uint _min_gain_p
    ) external initializer{
        require(address(_storageT) != address(0)
            && address(_nftRewards) != address(0)
            && address(_pairInfos) != address(0)
            && _usdtVaultFeeP + _lpFeeP + _sssFeeP == 100
            && _max_sl_p > 0 && _min_sl_p >= 0 && _max_gain_p > 0 && _min_gain_p >= 0, "WRONG_PARAMS");

        storageT = _storageT;
        nftRewards = _nftRewards;
        pairInfos = _pairInfos;

        usdtVaultFeeP = _usdtVaultFeeP;
        lpFeeP = _lpFeeP;
        sssFeeP = _sssFeeP;

        MAX_SL_P = _max_sl_p;
        MIN_SL_P = _min_sl_p;
        MAX_GAIN_P = _max_gain_p;
        MIN_GAIN_P = _min_gain_p;

        storageT.usdt().safeApprove(vaultToApprove, type(uint256).max);
    }

    // Modifiers
    modifier onlyGov(){
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyPriceAggregator(){
        require(msg.sender == address(storageT.priceAggregator()), "AGGREGATOR_ONLY");
        _;
    }
    modifier onlyAdlCallbacks(){
        require(msg.sender == storageT.adlCallbacks(), "CBSONLY");
        _;
    }
    modifier notDone(){
        require(!isDone, "DONE");
        _;
    }

    function setPairInfos(address _pairInfos) external onlyGov{
        require(_pairInfos != address(0));
        pairInfos = IPEXPairInfos(_pairInfos);
        emit AddressUpdated("pairInfos", _pairInfos);
    }

    function setNftRewards(address _nftRewards) external onlyGov{
        require(_nftRewards != address(0));
        nftRewards = INftRewards(_nftRewards);
        emit AddressUpdated("nftRewards", _nftRewards);
    }

    function setSLTP(uint _max_sl_p, uint _min_sl_p, uint _max_gain_p, uint _min_gain_p) external onlyGov{
        require(_max_sl_p > 0 && _min_sl_p >= 0 && _max_gain_p > 0 && _min_gain_p >= 0, "WRONG_PARAM");
        MAX_SL_P = _max_sl_p;
        MIN_SL_P = _min_sl_p;
        MAX_GAIN_P = _max_gain_p;
        MIN_GAIN_P = _min_gain_p;
        emit SLTPParamsUpdaated(_max_sl_p, _min_sl_p, _max_gain_p, _min_gain_p);
    }

    // Manage params
    function setClosingFeeSharesP(
        uint _usdtVaultFeeP,
        uint _lpFeeP,
        uint _sssFeeP
    ) external onlyGov{

        require(_usdtVaultFeeP + _lpFeeP + _sssFeeP == 100, "SUM_NOT_100");
        
        usdtVaultFeeP = _usdtVaultFeeP;
        lpFeeP = _lpFeeP;
        sssFeeP = _sssFeeP;

        emit ClosingFeeSharesPUpdated(_usdtVaultFeeP, _lpFeeP, _sssFeeP);
    }

    // Manage state
    function pause() external onlyGov{
        isPaused = !isPaused;

        emit Pause(isPaused); 
    }
    function done() external onlyGov{
        isDone = !isDone;

        emit Done(isDone); 
    }

    // Callbacks
    function openTradeMarketCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone{

        IStorageT.PendingMarketOrder memory o = 
            storageT.reqID_pendingMarketOrder(a.orderId);

        if(o.block == 0){ return; }
        
        IStorageT.Trade memory t = o.trade;

        (uint priceImpactP, uint priceAfterImpact) = pairInfos.getTradePriceImpact(
            marketExecutionPrice(a.price, a.spreadP, o.spreadReductionP, t.buy),
            t.pairIndex,
            t.buy,
            t.positionSizeUsdt * t.leverage
        );

        t.openPrice = priceAfterImpact;

        uint maxSlippage = o.wantedPrice * o.slippageP / 100 / PRECISION;

        if(isPaused || a.price == 0
        || (t.buy ?
            t.openPrice > o.wantedPrice + maxSlippage :
            t.openPrice < o.wantedPrice - maxSlippage)
        || (t.tp > 0 && (t.buy ?
            t.openPrice >= t.tp :
            t.openPrice <= t.tp))
        || (t.sl > 0 && (t.buy ?
            t.openPrice <= t.sl :
            t.openPrice >= t.sl))
        || !withinExposureLimits(t.pairIndex, t.buy, t.positionSizeUsdt, t.leverage)
        || priceImpactP * t.leverage > pairInfos.maxNegativePnlOnOpenP()){

            uint devGovFeesUsdt = storageT.handleDevGovFees(
                t.pairIndex, 
                t.positionSizeUsdt * t.leverage
            );
            storageT.transferUsdt(address(storageT), storageT.gov(), devGovFeesUsdt);

            storageT.transferUsdt(
                address(storageT),
                t.trader,
                t.positionSizeUsdt - devGovFeesUsdt
            );

            emit DevGovFeeCharged(t.trader, devGovFeesUsdt);

            emit MarketOpenCanceled(
                a.orderId,
                t.trader,
                t.pairIndex
            );

        }else{
            uint devGovFeesUsdt = storageT.handleDevGovFees(t.pairIndex, t.positionSizeUsdt * t.leverage);

            IStorageT.Trade memory finalTrade = registerTrade(
                t, 1500, 0
            );

            emit MarketExecuted(
                a.orderId,
                finalTrade.trader,
                finalTrade,
                true,
                finalTrade.openPrice,
                priceImpactP,
                finalTrade.initialPosUSDT / PRECISION,
                0,
                0,
                0,
                0,
                devGovFeesUsdt
            );
        }

        storageT.unregisterPendingMarketOrder(a.orderId, true);
    }

    function closeTradeMarketCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone{
        
        IStorageT.PendingMarketOrder memory o = storageT.reqID_pendingMarketOrder(
            a.orderId
        );

        if(o.block == 0){ return; }

        IStorageT.Trade memory t = storageT.openTrades(
            o.trade.trader, o.trade.pairIndex, o.trade.index
        );

        if(t.leverage > 0){
            IStorageT.TradeInfo memory i = storageT.openTradesInfo(
                t.trader, t.pairIndex, t.index
            );

            IAggregator aggregator = storageT.priceAggregator();
            IPairsStorage pairsStorage = aggregator.pairsStorage();
            
            Values memory v;

            v.levPosUsdt = t.initialPosUSDT * t.leverage / PRECISION;

            if(a.price == 0){

                // Dev / gov rewards to pay for oracle cost
                // Charge in USDT if collateral in storage or token if collateral in vault
                v.reward1 = storageT.handleDevGovFees(
                        t.pairIndex,
                        v.levPosUsdt
                    );
                storageT.transferUsdt(address(storageT), storageT.gov(), v.reward1);
                t.initialPosUSDT -= v.reward1 * PRECISION;
                storageT.updateTrade(t);

                emit DevGovFeeCharged(t.trader, v.reward1);

                emit MarketCloseCanceled(
                    a.orderId,
                    t.trader,
                    t.pairIndex,
                    t.index
                );

            }else{
                v.profitP = currentPercentProfit(t.openPrice, a.price, t.buy, t.leverage);
                v.posUsdt = v.levPosUsdt / t.leverage;
                
                Fees memory fees;
                (v.usdtSentToTrader, fees) = unregisterTrade(
                    t,
                    v.profitP,
                    v.posUsdt,
                    i.openInterestUsdt / t.leverage,
                    v.levPosUsdt * pairsStorage.pairCloseFeeP(t.pairIndex) / 100 / PRECISION
                );

                emit MarketExecuted(
                    a.orderId,
                    t.trader,
                    t,
                    false,
                    a.price,
                    0,
                    v.posUsdt,
                    eventPercentProfit(v.posUsdt, v.usdtSentToTrader),
                    v.usdtSentToTrader,
                    fees.rolloverFee,
                    fees.fundingFee,
                    fees.closingFee
                );
            }
        }

        storageT.unregisterPendingMarketOrder(a.orderId, false);
    }

    function executeNftOpenOrderCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone{

        IStorageT.PendingNftOrder memory n = storageT.reqID_pendingNftOrder(a.orderId);

        if(!isPaused && a.price > 0
        && storageT.hasOpenLimitOrder(n.trader, n.pairIndex, n.index)
        && block.number >= storageT.nftLastSuccess(n.nftId) + storageT.nftSuccessTimelock()){

            IStorageT.OpenLimitOrder memory o = storageT.getOpenLimitOrder(
                n.trader, n.pairIndex, n.index
            );

            INftRewards.OpenLimitOrderType t = nftRewards.openLimitOrderTypes(
                n.trader, n.pairIndex, n.index
            );

            (uint priceImpactP, uint priceAfterImpact) = pairInfos.getTradePriceImpact(
                marketExecutionPrice(a.price, a.spreadP, o.spreadReductionP, o.buy),
                o.pairIndex,
                o.buy,
                o.positionSize * o.leverage
            );

            a.price = priceAfterImpact;

            if((t == INftRewards.OpenLimitOrderType.LEGACY ?
                    (a.price >= o.minPrice && a.price <= o.maxPrice) :
                t == INftRewards.OpenLimitOrderType.REVERSAL ?
                    (o.buy ?
                        a.price <= o.maxPrice :
                        a.price >= o.minPrice) :
                    (o.buy ?
                        a.price >= o.minPrice :
                        a.price <= o.maxPrice))
                && withinExposureLimits(o.pairIndex, o.buy, o.positionSize, o.leverage)
                && priceImpactP * o.leverage <= pairInfos.maxNegativePnlOnOpenP()){

                if(o.buy){
                    o.maxPrice = a.price < o.maxPrice ? a.price : o.maxPrice ;
                } else {
                    o.maxPrice = a.price > o.maxPrice ? a.price : o.maxPrice ;
                }

                IStorageT.Trade memory finalTrade = registerTrade(
                    IStorageT.Trade(
                        o.trader,
                        o.pairIndex,
                        0,
                        0,
                        o.positionSize,
                        t == INftRewards.OpenLimitOrderType.REVERSAL ?
                            o.maxPrice : // o.minPrice = o.maxPrice in that case
                            a.price,
                        o.buy,
                        o.leverage,
                        o.tp,
                        o.sl
                    ), 
                    n.nftId,
                    n.index
                );

                uint devGovFeesUsdt = storageT.handleDevGovFees(o.pairIndex, o.positionSize * o.leverage);

                storageT.unregisterOpenLimitOrder(o.trader, o.pairIndex, o.index);

                emit LimitExecuted(
                    a.orderId,
                    finalTrade.trader,
                    n.index,
                    finalTrade,
                    n.nftHolder,
                    IStorageT.LimitOrder.OPEN,
                    finalTrade.openPrice,
                    priceImpactP,
                    finalTrade.initialPosUSDT / PRECISION,
                    0,
                    0,
                    0,
                    0,
                    devGovFeesUsdt
                );
            }
        }

        nftRewards.unregisterTrigger(
            INftRewards.TriggeredLimitId(n.trader, n.pairIndex, n.index, n.orderType)
        );

        storageT.unregisterPendingNftOrder(a.orderId);
    }

    function executeNftCloseOrderCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone{
        
        IStorageT.PendingNftOrder memory o = storageT.reqID_pendingNftOrder(a.orderId);

        IStorageT.Trade memory t = storageT.openTrades(
            o.trader, o.pairIndex, o.index
        );

        IAggregator aggregator = storageT.priceAggregator();

        if(a.price > 0 && t.leverage > 0
        && block.number >= storageT.nftLastSuccess(o.nftId) + storageT.nftSuccessTimelock()){

            IStorageT.TradeInfo memory i = storageT.openTradesInfo(
                t.trader, t.pairIndex, t.index
            );

            IPairsStorage pairsStored = aggregator.pairsStorage();
            
            Values memory v;

            v.price =
                pairsStored.guaranteedSlEnabled(t.pairIndex) ?
                    o.orderType == IStorageT.LimitOrder.TP ?
                        t.tp : 
                    o.orderType == IStorageT.LimitOrder.SL ?
                        t.sl :
                    a.price :
                a.price;

            v.profitP = currentPercentProfit(t.openPrice, v.price, t.buy, t.leverage);
            v.levPosUsdt = t.initialPosUSDT * t.leverage / PRECISION;
            v.posUsdt = v.levPosUsdt / t.leverage;

            if(o.orderType == IStorageT.LimitOrder.LIQ){

                v.liqPrice = pairInfos.getTradeLiquidationPrice(
                    t.trader,
                    t.pairIndex,
                    t.index,
                    t.openPrice,
                    t.buy,
                    v.posUsdt,
                    t.leverage
                );

                // NFT reward in USDT
                v.reward1 = (t.buy ?
                        a.price <= v.liqPrice :
                        a.price >= v.liqPrice
                    ) ?
                        v.posUsdt * 5 / 100 : 0;

            }else{

                // NFT reward in USDT
                v.reward1 =
                    (o.orderType == IStorageT.LimitOrder.TP && t.tp > 0 &&
                        (t.buy ?
                            a.price >= t.tp :
                            a.price <= t.tp)
                    ||
                    o.orderType == IStorageT.LimitOrder.SL && t.sl > 0 &&
                        (t.buy ?
                            a.price <= t.sl :
                            a.price >= t.sl)
                    ) ? 1 : 0;
            }

            // If can be triggered
            if(v.reward1 > 0){
                
                Fees memory fees;
                (v.usdtSentToTrader, fees) = unregisterTrade(
                    t,
                    v.profitP,
                    v.posUsdt,
                    i.openInterestUsdt / t.leverage,
                    v.levPosUsdt * pairsStored.pairCloseFeeP(t.pairIndex) / 100 / PRECISION
                );

                // Convert NFT bot fee from USDT to token value
                v.reward2 = 0;

                nftRewards.distributeNftReward(
                    INftRewards.TriggeredLimitId(o.trader, o.pairIndex, o.index, o.orderType),
                    v.reward2
                );

                storageT.increaseNftRewards(o.nftId, v.reward2);

                emit LimitExecuted(
                    a.orderId,
                    t.trader,
                    o.index,
                    t,
                    o.nftHolder,
                    o.orderType,
                    v.price,
                    0,
                    v.posUsdt,
                    eventPercentProfit(v.posUsdt, v.usdtSentToTrader),
                    v.usdtSentToTrader,
                    fees.rolloverFee,
                    fees.fundingFee,
                    fees.closingFee
                );
            }
        }

        nftRewards.unregisterTrigger(
            INftRewards.TriggeredLimitId(o.trader, o.pairIndex, o.index, o.orderType)
        );

        storageT.unregisterPendingNftOrder(a.orderId);
    }

    function updateSlCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone{
        
        IAggregator aggregator = storageT.priceAggregator();
        IAggregator.PendingSl memory o = aggregator.pendingSlOrders(a.orderId);
        
        IStorageT.Trade memory t = storageT.openTrades(
            o.trader, o.pairIndex, o.index
        );

        if(t.leverage > 0){

            Values memory v;
            v.levPosUsdt = t.initialPosUSDT * t.leverage / PRECISION / 4;

            v.reward1 = storageT.handleDevGovFees(
                    t.pairIndex,
                    v.levPosUsdt
                );
            storageT.transferUsdt(address(storageT), storageT.gov(), v.reward1);
            t.initialPosUSDT -= v.reward1 * PRECISION;
            storageT.updateTrade(t);

            emit DevGovFeeCharged(t.trader, v.reward1);

            if(a.price > 0 && t.buy == o.buy && t.openPrice == o.openPrice
            && (t.buy ?
                o.newSl <= a.price :
                o.newSl >= a.price)
            ){
                storageT.updateSl(o.trader, o.pairIndex, o.index, o.newSl);

                emit SlUpdated(
                    a.orderId,
                    o.trader,
                    o.pairIndex,
                    o.index,
                    o.newSl
                );
                
            }else{
                emit SlCanceled(
                    a.orderId,
                    o.trader,
                    o.pairIndex,
                    o.index
                );
            }
        }

        aggregator.unregisterPendingSlOrder(a.orderId);
    }

    // Shared code between market & limit callbacks
    function registerTrade(
        IStorageT.Trade memory trade, 
        uint nftId, 
        uint limitIndex
    ) private returns(IStorageT.Trade memory){

        IAggregator aggregator = storageT.priceAggregator();
        IPairsStorage pairsStored = aggregator.pairsStorage();

        Values memory v;

        v.levPosUsdt = trade.positionSizeUsdt * trade.leverage;

        // Charge opening fee
        v.reward2 = storageT.handleDevGovFees(trade.pairIndex, v.levPosUsdt);
        storageT.transferUsdt(address(storageT), storageT.gov(), v.reward2);

        trade.positionSizeUsdt -= v.reward2;

        emit DevGovFeeCharged(trade.trader, v.reward2);

        // Distribute NFT fee and send USDT amount to vault
        if(nftId < 1500){
            v.reward3 = 0;

            nftRewards.distributeNftReward(
                INftRewards.TriggeredLimitId(
                    trade.trader, trade.pairIndex, limitIndex, IStorageT.LimitOrder.OPEN
                ), v.reward3
            );

            storageT.increaseNftRewards(nftId, v.reward3);
        }

        // Set trade final details
        trade.index = storageT.firstEmptyTradeIndex(trade.trader, trade.pairIndex);
        trade.initialPosUSDT = trade.positionSizeUsdt * PRECISION;

        trade.tp = correctTp(trade.openPrice, trade.leverage, trade.tp, trade.buy);
        trade.sl = correctSl(trade.openPrice, trade.leverage, trade.sl, trade.buy);

        // Store final trade in storage contract
        storageT.storeTrade(
            trade,
            IStorageT.TradeInfo(
                trade.positionSizeUsdt * trade.leverage,
                block.number,
                0,
                0,
                false
            )
        );

        // Call other contracts
        pairInfos.storeTradeInitialAccFees(trade.trader, trade.pairIndex, trade.index, trade.buy);
        pairsStored.updateGroupCollateral(trade.pairIndex, trade.positionSizeUsdt, trade.buy, true);
        storageT.increaseUpnlLastId();

        return trade;
    }

    function unregisterTrade(
        IStorageT.Trade memory trade,
        int percentProfit,   // PRECISION
        uint currentUsdtPos,
        uint initialUsdtPos,
        uint closingFeeUsdt
    ) private returns(uint usdtSentToTrader, Fees memory fees){
        uint rolloverFee;
        Values memory v;
        
        fees.rolloverFee = pairInfos.getTradeRolloverFee(trade.trader, trade.pairIndex, trade.index, currentUsdtPos);
        fees.fundingFee = pairInfos.getTradeFundingFee(trade.trader, trade.pairIndex, trade.index, trade.buy, currentUsdtPos, trade.leverage);
        fees.closingFee = closingFeeUsdt * usdtVaultFeeP / 100;

        // Calculate net PnL (after all closing fees)
        (usdtSentToTrader, rolloverFee) = pairInfos.getTradeValue(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy,
            currentUsdtPos,
            trade.leverage,
            percentProfit,
            fees.closingFee
        );

        // If collateral in storage (opened after update)
        if(trade.positionSizeUsdt > 0){

            // rollover fee and closing fee to govAddr
            v.reward2 = fees.closingFee + fees.rolloverFee;
            storageT.transferUsdt(address(storageT), storageT.gov(), v.reward2);
            
            emit ClosingRolloverFeeCharged(trade.trader, v.reward2);

            // Take USDT from vault if winning trade
            // or send USDT to vault if losing trade
            uint usdtLeftInStorage = currentUsdtPos - v.reward2;

            if(usdtSentToTrader > usdtLeftInStorage){
                storageT.vault().sendAssets(usdtSentToTrader - usdtLeftInStorage, trade.trader);
                storageT.transferUsdt(address(storageT), trade.trader, usdtLeftInStorage);

            }else{
                sendToVault(usdtLeftInStorage - usdtSentToTrader, trade.trader); // funding fee & reward
                storageT.transferUsdt(address(storageT), trade.trader, usdtSentToTrader);
            }

        }else{
            storageT.vault().sendAssets(usdtSentToTrader, trade.trader);
        }

        // Calls to other contracts
        storageT.priceAggregator().pairsStorage().updateGroupCollateral(
            trade.pairIndex, initialUsdtPos, trade.buy, false
        );

        // Unregister trade
        storageT.unregisterTrade(trade.trader, trade.pairIndex, trade.index);
        storageT.increaseUpnlLastId();
    }

    // Utils
    function withinExposureLimits(
        uint pairIndex,
        bool buy,
        uint positionSizeUsdt,
        uint leverage
    ) public view returns(bool){
        IPairsStorage pairsStored = storageT.priceAggregator().pairsStorage();
        
        return storageT.openInterestUsdt(pairIndex, buy ? 0 : 1)
            + positionSizeUsdt * leverage <= storageT.openInterestUsdt(pairIndex, 2)
            && pairsStored.groupCollateral(pairIndex, buy)
            + positionSizeUsdt <= pairsStored.groupMaxCollateral(pairIndex);
    }
    function currentPercentProfit(
        uint openPrice,
        uint currentPrice,
        bool buy,
        uint leverage
    ) private view returns(int p){
        int maxPnlP = int(MAX_GAIN_P) * int(PRECISION);
        
        p = (buy ?
                int(currentPrice) - int(openPrice) :
                int(openPrice) - int(currentPrice)
            ) * 100 * int(PRECISION) * int(leverage) / int(openPrice);

        p = p > maxPnlP ? maxPnlP : p;
    }
    function eventPercentProfit(
        uint positionSizeUsdt,
        uint usdtSentToTrader
    ) private pure returns(int p){ // PRECISION (%)
        require(positionSizeUsdt > 0, "WRONG_PARAMS");
        int pnl = int(usdtSentToTrader) - int(positionSizeUsdt);
        p = pnl * 100 * int(PRECISION) / int(positionSizeUsdt);
    }
    function correctTp(
        uint openPrice,
        uint leverage,
        uint tp,
        bool buy
    ) private view returns(uint){
        if(tp == 0
        || currentPercentProfit(openPrice, tp, buy, leverage) == int(MAX_GAIN_P) * int(PRECISION)){

            uint tpDiff = openPrice * MAX_GAIN_P / leverage / 100;

            return buy ? 
                openPrice + tpDiff :
                tpDiff <= openPrice ?
                    openPrice - tpDiff :
                0;
        }
        
        return tp;
    }
    function correctSl(
        uint openPrice,
        uint leverage,
        uint sl,
        bool buy
    ) private view returns(uint){
        if(sl > 0
        && currentPercentProfit(openPrice, sl, buy, leverage) < int(MAX_SL_P) * int(PRECISION) * -1){

            uint slDiff = openPrice * MAX_SL_P / leverage / 100;

            return buy ?
                openPrice - slDiff :
                openPrice + slDiff;
        }
        
        return sl;
    }
    function marketExecutionPrice(
        uint price,
        uint spreadP,
        uint spreadReductionP,
        bool long
    ) private pure returns (uint){
        uint priceDiff = price * (spreadP - spreadP * spreadReductionP / 100) / 100 / PRECISION;

        return long ?
            price + priceDiff :
            price - priceDiff;
    }

    function sendToVault(uint amountUsdt, address trader) private{
        storageT.transferUsdt(address(storageT), address(this), amountUsdt);
        storageT.vault().receiveAssets(amountUsdt, trader);
    }

    // for adlcallbacks
    function adlSendToVault(uint amountUsdt, address trader) external onlyAdlCallbacks{
        sendToVault(amountUsdt, trader);
    }

    function adlVaultSendToTrader(uint amountUsdt, address trader) external onlyAdlCallbacks{
        storageT.vault().sendAssets(amountUsdt, trader);
    }
}
