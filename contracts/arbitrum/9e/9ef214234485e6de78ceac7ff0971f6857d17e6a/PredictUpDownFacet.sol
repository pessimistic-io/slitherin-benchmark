// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Constants.sol";
import "./TransferHelper.sol";
import "./OnlySelf.sol";
import "./IVault.sol";
import "./IFeeManager.sol";
import {RequestType, IPriceFacade} from "./IPriceFacade.sol";
import "./IPredictUpDown.sol";
import "./ITradingConfig.sol";
import {IPredictionManager, PredictionPeriod, PredictionPairStatus} from "./IPredictionManager.sol";
import "./LibPredictUpDown.sol";
import "./LibAccessControlEnumerable.sol";

contract PredictUpDownFacet is IPredictUpDown, OnlySelf {

    using TransferHelper for address;

    function predictAndBet(PredictionInput memory pi) external override {
        _predictAndBet(pi);
    }

    function predictAndBetBNB(PredictionInput memory pi) external payable override {
        pi.tokenIn = TransferHelper.nativeWrapped();
        pi.amountIn = uint96(msg.value);
        _predictAndBet(pi);
    }

    function _predictAndBet(PredictionInput memory pi) private {
        LibPredictUpDown.PredictionUpDownStorage storage puds = LibPredictUpDown.predictionUpDownStorage();
        uint256 openFee = _predictCheck(puds, pi);
        pi.tokenIn.transferFrom(msg.sender, pi.amountIn);
        // Generate prediction data
        PendingPrediction memory pendingPrediction = PendingPrediction(
            pi.tokenIn, pi.amountIn, pi.predictionPairBase, uint96(openFee), msg.sender,
            pi.price, pi.broker, pi.isUp, uint128(Constants.arbSys.arbBlockNumber()), pi.period
        );
        puds.pendingPredictions[++puds.id] = pendingPrediction;
        puds.pendingPredictionAmountIns[pi.tokenIn] += pi.amountIn;
        // Request feed price.
        IPriceFacade(address(this)).requestPrice(bytes32(puds.id), pi.predictionPairBase, RequestType.PREDICT);
        emit PredictAndBetPending(msg.sender, puds.id, pendingPrediction);
    }

    function _predictCheck(
        LibPredictUpDown.PredictionUpDownStorage storage puds, PredictionInput memory pi
    ) private returns (uint256 openFee)  {
        // Check global state switch.
        ITradingConfig.PredictionConfig memory pc = ITradingConfig(address(this)).getPredictionConfig();
        require(pc.predictionBet, "PredictUpDownFacet: The Market Closed");
        // Check if tokenIn is supported.
        IVault.MarginToken memory mt = IVault(address(this)).getTokenForPrediction(pi.tokenIn);
        require(mt.switchOn, "PredictUpDownFacet: Bets with this token is not supported");
        uint256 amountInUsd = pi.amountIn * mt.price * 1e10 / (10 ** mt.decimals);
        // Check if the minimum input amount is met
        require(amountInUsd >= pc.minBetUsd, "PredictUpDownFacet: The principal is too small");
        // Check the prediction pair period status.
        PredictionPeriod memory pp = IPredictionManager(address(this)).getPredictionPeriod(pi.predictionPairBase, pi.period);
        require(
            pp.winRatio > 0 && pp.status == PredictionPairStatus.AVAILABLE,
            "PredictUpDownFacet: The pair or period is closed"
        );
        // Check if the input exceeds the market limit.
        PredictionMarket storage pm = puds.pairPeriodPredictionMarkets[pi.predictionPairBase][pi.period];
        openFee = pi.amountIn * pp.openFeeP / 1e4;
        uint256 betAmountUsd = amountInUsd - openFee * mt.price * 1e10 / (10 ** mt.decimals);
        require(
            (pi.isUp && betAmountUsd + pm.upUsd <= pp.maxUpUsd) || (!pi.isUp && betAmountUsd + pm.downUsd <= pp.maxDownUsd),
            "PredictUpDownFacet: Insufficient current open predictions"
        );
        return openFee;
    }

    function predictionCallback(bytes32 id, uint256 price) external onlySelf override {
        uint256 pId = uint256(id);
        LibPredictUpDown.PredictionUpDownStorage storage puds = LibPredictUpDown.predictionUpDownStorage();
        PendingPrediction storage pp = puds.pendingPredictions[pId];
        if (pp.amountIn == 0) {
            return;
        }
        IVault.MarginToken memory mt = IVault(address(this)).getTokenForPrediction(pp.tokenIn);
        uint256 betAmountUsd = (pp.amountIn - pp.openFee) * mt.price * 1e10 / (10 ** mt.decimals);
        PredictionRefund refund = _predictionCallbackCheck(puds, pp, price, betAmountUsd);
        if (refund != PredictionRefund.NO) {
            (address tokenIn, address user, uint256 amountIn) = (pp.tokenIn, pp.user, pp.amountIn);
            // clear pending data
            puds.pendingPredictionAmountIns[tokenIn] -= amountIn;
            delete puds.pendingPredictions[pId];

            tokenIn.transfer(user, amountIn);
            emit PendingPredictionRefund(user, pId, refund);
        } else {
            _predictionDeal(puds, pp, pId, price, betAmountUsd);
            // clear pending data
            puds.pendingPredictionAmountIns[pp.tokenIn] -= pp.amountIn;
            delete puds.pendingPredictions[pId];
        }
    }

    function _predictionCallbackCheck(
        LibPredictUpDown.PredictionUpDownStorage storage puds, PendingPrediction storage pp,
        uint256 price, uint256 betAmountUsd
    ) private returns (PredictionRefund refund) {
        // Check if the price feed is delayed
        if (pp.blockNumber + Constants.FEED_DELAY_BLOCK < Constants.arbSys.arbBlockNumber()) {
            return PredictionRefund.FEED_DELAY;
        }
        // Check if the fed price meets the price acceptable to the user
        if ((pp.isUp && price > pp.price) || (!pp.isUp && price < pp.price)) {
            return PredictionRefund.USER_PRICE;
        }
        PredictionPeriod memory predictionPeriod = IPredictionManager(address(this)).getPredictionPeriod(pp.predictionPairBase, pp.period);
        PredictionMarket storage pm = puds.pairPeriodPredictionMarkets[pp.predictionPairBase][pp.period];
        if (
            (pp.isUp && pm.upUsd + uint96(betAmountUsd) > predictionPeriod.maxUpUsd)
            ||
            (!pp.isUp && pm.downUsd + uint96(betAmountUsd) > predictionPeriod.maxDownUsd)
        ) {
            return PredictionRefund.MAX_OI;
        }
        return PredictionRefund.NO;
    }

    function _predictionDeal(
        LibPredictUpDown.PredictionUpDownStorage storage puds, PendingPrediction storage pp,
        uint256 id, uint256 price, uint256 betAmountUsd
    ) private {
        uint24 broker = pp.broker;
        if (pp.openFee > 0) {
            broker = IFeeManager(address(this)).chargePredictionOpenFee(pp.tokenIn, pp.openFee, pp.broker);
        }
        uint256[] storage ids = puds.userOpenPredictionIds[pp.user];
        uint96 betAmount = pp.amountIn - pp.openFee;
        OpenPrediction memory op = OpenPrediction(
            pp.tokenIn, betAmount, pp.predictionPairBase, pp.openFee, pp.user, uint96(betAmountUsd),
            uint32(ids.length), uint64(price), uint40(block.timestamp), broker, pp.isUp, pp.period
        );
        puds.openPredictions[id] = op;
        ids.push(id);
        puds.openPredictionAmountIns[pp.tokenIn] += betAmount;
        if (pp.isUp) {
            puds.pairPeriodPredictionMarkets[pp.predictionPairBase][pp.period].upUsd += uint96(betAmountUsd);
        } else {
            puds.pairPeriodPredictionMarkets[pp.predictionPairBase][pp.period].downUsd += uint96(betAmountUsd);
        }
        emit PredictAndBet(pp.user, id, op);
    }

    function settlePredictions(SettlePrediction[] calldata arr) external override {
        LibAccessControlEnumerable.checkRole(Constants.PREDICTION_KEEPER_ROLE);
        // Check global state switch.
        ITradingConfig.PredictionConfig memory pc = ITradingConfig(address(this)).getPredictionConfig();
        require(pc.predictionSettle, "PredictUpDownFacet: The Market Closed");
        LibPredictUpDown.PredictionUpDownStorage storage puds = LibPredictUpDown.predictionUpDownStorage();
        for (UC i = ZERO; i < uc(arr.length); i = i + ONE) {
            SettlePrediction memory sp = arr[i.into()];
            _settlePredictionById(puds, sp.id, sp.price);
        }
    }

    function _settlePredictionById(
        LibPredictUpDown.PredictionUpDownStorage storage puds, uint256 id, uint64 price
    ) private {
        OpenPrediction storage op = puds.openPredictions[id];
        if (op.betAmount == 0) {
            return;
        }
        // Check the prediction pair period status.
        PredictionPeriod memory pp = IPredictionManager(address(this)).getPredictionPeriod(op.predictionPairBase, op.period);
        require(pp.status != PredictionPairStatus.CLOSED, "PredictUpDownFacet: The pair or period is closed");
        // Check if prediction are due
        if (op.startTime + _periodDuration(op.period) > block.timestamp) {
            emit SettlePredictionReject(id, op.period, op.startTime + _periodDuration(op.period));
            return;
        }
        (bool available,,) = IPriceFacade(address(this)).confirmTriggerPrice(op.predictionPairBase, price);
        if (!available) {
            emit SettlePredictionReject(id, op.period, op.startTime + _periodDuration(op.period));
            return;
        }
        puds.openPredictionAmountIns[op.tokenIn] -= op.betAmount;
        if (op.isUp) {
            puds.pairPeriodPredictionMarkets[op.predictionPairBase][op.period].upUsd -= uint96(op.betAmountUsd);
        } else {
            puds.pairPeriodPredictionMarkets[op.predictionPairBase][op.period].downUsd -= uint96(op.betAmountUsd);
        }
        // win
        if ((op.isUp && price > op.entryPrice) || (!op.isUp && price < op.entryPrice)) {
            uint256 closeFee = op.betAmount * pp.winCloseFeeP / 1e4;
            if (closeFee > 0) {
                IFeeManager(address(this)).chargePredictionCloseFee(op.tokenIn, closeFee, op.broker);
            }
            uint256 profit = op.betAmount * pp.winRatio / 1e4;
            IVault(address(this)).decrease(op.tokenIn, profit);
            (address tokenIn,address user,uint256 betAmount) = (op.tokenIn, op.user, op.betAmount);
            _removeOpenPrediction(puds, op, id);

            tokenIn.transfer(user, betAmount + profit - closeFee);
            emit SettlePredictionSuccessful(id, true, price, tokenIn, profit, closeFee);
        } else { // loss
            uint256 closeFee = op.betAmount * pp.loseCloseFeeP / 1e4;
            IVault(address(this)).increase(op.tokenIn, op.betAmount);
            emit SettlePredictionSuccessful(id, false, price, op.tokenIn, op.betAmount - closeFee, closeFee);
            _removeOpenPrediction(puds, op, id);
        }
    }

    function _removeOpenPrediction(
        LibPredictUpDown.PredictionUpDownStorage storage puds, OpenPrediction storage op, uint256 id
    ) private {
        uint256[] storage userIds = puds.userOpenPredictionIds[op.user];
        uint256 last = userIds.length - 1;
        uint256 opIndex = op.userOpenPredictIndex;
        if (opIndex != last) {
            uint256 lastId = userIds[last];
            userIds[opIndex] = lastId;
            puds.openPredictions[lastId].userOpenPredictIndex = uint32(opIndex);
        }
        userIds.pop();
        delete puds.openPredictions[id];
    }

    function _periodDuration(Period period) private pure returns (uint256) {
        if (period == Period.MINUTE1) {
            return 1 minutes;
        } else if (period == Period.MINUTE5) {
            return 5 minutes;
        } else if (period == Period.MINUTE10) {
            return 10 minutes;
        } else if (period == Period.MINUTE15) {
            return 15 minutes;
        } else if (period == Period.MINUTE30) {
            return 30 minutes;
        } else if (period == Period.HOUR1) {
            return 1 hours;
        } else if (period == Period.HOUR2) {
            return 2 hours;
        } else if (period == Period.HOUR3) {
            return 3 hours;
        } else if (period == Period.HOUR4) {
            return 4 hours;
        } else if (period == Period.HOUR6) {
            return 6 hours;
        } else if (period == Period.HOUR8) {
            return 8 hours;
        } else if (period == Period.HOUR12) {
            return 12 hours;
        } else {
            return 1 days;
        }
    }

    function getPredictionById(uint256 id) public view override returns (PredictionView memory) {
        OpenPrediction storage op = LibPredictUpDown.predictionUpDownStorage().openPredictions[id];
        return PredictionView(
            id, op.tokenIn, op.betAmount, op.predictionPairBase, op.openFee,
            op.entryPrice, op.startTime, op.isUp, op.period
        );
    }

    function getPredictions(address user, address predictionPairBase) external view override returns (PredictionView[] memory) {
        uint256[] storage ids = LibPredictUpDown.predictionUpDownStorage().userOpenPredictionIds[user];
        if (predictionPairBase == address(0)) {
            PredictionView[] memory predictions = new PredictionView[](ids.length);
            for (uint i; i < ids.length; i++) {
                predictions[i] = getPredictionById(ids[i]);
            }
            return predictions;
        } else {
            PredictionView[] memory _predictions = new PredictionView[](ids.length);
            uint count;
            for (uint i; i < ids.length; i++) {
                PredictionView memory p = getPredictionById(ids[i]);
                if (p.predictionPairBase == predictionPairBase) {
                    count++;
                }
                _predictions[i] = p;
            }
            PredictionView[] memory predictions = new PredictionView[](count);
            uint index;
            for (uint i; i < ids.length; i++) {
                PredictionView memory p = _predictions[i];
                if (p.predictionPairBase == predictionPairBase) {
                    predictions[index] = p;
                    index++;
                }
            }
            return predictions;
        }
    }

    function getPredictionMarket(
        address predictionPairBase, Period[] calldata periods
    ) external view override returns (PredictionMarket[] memory) {
        LibPredictUpDown.PredictionUpDownStorage storage puds = LibPredictUpDown.predictionUpDownStorage();
        PredictionMarket[] memory pms = new PredictionMarket[](periods.length);
        for (UC i = ZERO; i < uc(periods.length); i = i + ONE) {
            pms[i.into()] = puds.pairPeriodPredictionMarkets[predictionPairBase][periods[i.into()]];
        }
        return pms;
    }
}

