// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./BotSimulationLib.sol";
import "./Errors.sol";
import "./SpecSegmentLib.sol";
import "./BotDecisionHelperBase.sol";
import "./IBotDecisionHelper.sol";
import "./ILongYieldTradingBot.sol";

contract LongYieldDecisionHelper is BotDecisionHelperBase {
    using MarketExtLib for MarketExtState;
    using MarketExtLib for ApproxParams;
    using MarketMathCore for MarketState;
    using MarketApproxPtInLib for MarketState;
    using BotSimulationLib for BotState;
    using PYIndexLib for PYIndex;
    using Math for uint256;
    using Math for int256;
    using LogExpMath for uint256;
    using SpecSegmentLib for TradingSpecs;

    uint256 public constant DUST_AMOUNT = 1000;

    function getRebalanceAction(
        address botAddress
    ) public view returns (RebalanceOutput memory output) {
        StrategyData memory strategyData = ITradingBotBase(botAddress).readStrategyData();
        (uint256 tvlInSy, , uint256 floatingSyRatio, ) = _calcBotExtStats(
            strategyData.botState,
            strategyData.marketExt
        );

        uint256 lowerBound = strategyData.specs.targetSyRatio.mulDown(
            Math.ONE - strategyData.specs.bufferSyRatio
        );

        uint256 upperBound = strategyData.specs.targetSyRatio.mulDown(
            Math.ONE + strategyData.specs.bufferSyRatio
        );

        if (floatingSyRatio > upperBound) {
            output.rebalanceType = RebalanceType.AddLiqKeepYt;
            (output.amountIn, output.amountOut, output.amountOut2) = _calcSyAmountForZPI(
                strategyData.marketExt,
                tvlInSy,
                floatingSyRatio,
                strategyData.specs.targetSyRatio
            );
        } else if (floatingSyRatio < lowerBound) {
            (output.rebalanceType, output.amountIn, output.amountOut) = _calcRemoveRebalance(
                strategyData,
                tvlInSy
            );
        }
    }

    // We dont care about AddLiqKeepYt here
    function getTradeAction(address botAddress) public view returns (TradeResult memory res) {
        StrategyData memory strategyData = ILongYieldTradingBot(botAddress).readStrategyData();
        uint256 iy = strategyData.marketExt.impliedYield();

        res.currentBin = _getCurrentBin(strategyData.botState, strategyData.specs, iy);
        if (res.currentBin == 0) {
            res.action = TradeActionType.NONE;
            return res;
        }
        res.targetIy = _getTargetImpliedYieldForBin(
            strategyData.botState,
            strategyData.specs,
            res.currentBin
        );

        uint256 maxAmountForAction = INF;
        uint256 rebalanceAdditionalCheck;

        if (res.currentBin < 0) {
            if (strategyData.botState.lpBalance < DUST_AMOUNT) return res;
            res.action = TradeActionType.RemoveLiqToYt;
            maxAmountForAction = _calcTradeActionMaxAmount(
                strategyData.botState.lpBalance,
                res.currentBin,
                strategyData.botState.buyBins,
                strategyData.specs.numOfBins
            );

            if (maxAmountForAction == 0) {
                res.action = TradeActionType.NONE;
                return res;
            }
        } else {
            if (strategyData.botState.ytBalance < DUST_AMOUNT) return res;
            res.action = TradeActionType.AddLiqFromYt;
            uint256 maxYtToAddLiq = searchMaxYtToAddLiq(strategyData);

            rebalanceAdditionalCheck = _calcTradeActionMaxAmount(
                maxYtToAddLiq,
                res.currentBin,
                strategyData.botState.buyBins,
                strategyData.specs.numOfBins
            );

            if (rebalanceAdditionalCheck == 0) {
                res.action = TradeActionType.NONE;
                return res;
            }
        }

        res.guessBotParams = searchForBotParam(
            strategyData,
            res.action,
            res.targetIy,
            rebalanceAdditionalCheck,
            _getMockApproxParamsWithGuessMax(maxAmountForAction),
            _getMockApproxParams()
        );
        (res.amountOut, res.guessIntParams) = _calcTradeActionAmountOutAndIntParams(
            strategyData.marketExt,
            res.action,
            res.guessBotParams
        );
    }

    /**
     * Given the rebalancing action and its `botParam`, binary search for the optimal internal
     * parameter `intParam` for the internal action's approximation (e.g. for router's swap)
     */
    function _calcTradeActionAmountOutAndIntParams(
        MarketExtState memory marketExt,
        TradeActionType action,
        uint256 botParam
    ) public pure returns (uint256 amountOut, uint256 intParams) {
        if (action == TradeActionType.RemoveLiqToYt) {
            (amountOut, intParams) = marketExt.clone().removeLiqToYt(
                botParam,
                _getMockApproxParams()
            );
        } else {
            (amountOut, ) = marketExt.clone().addLiqFromYt(botParam);
        }
    }

    /**
     * Binary search for max amount of YT to add liquidity so that it doesnt exceed the specs' yt/pt ratio
     */
    function searchMaxYtToAddLiq(
        StrategyData memory strategyData
    ) public pure returns (uint256 maxYtToAddLiq) {
        (, , , uint256 ytPtRatioAfter) = _calcBotExtStats(
            strategyData.botState,
            strategyData.marketExt
        );
        if (ytPtRatioAfter < strategyData.specs.minYtPtRatio) {
            return 0;
        }

        ApproxParams memory guessParams = _getMockApproxParamsWithGuessMax(
            _weakUpperBound(
                strategyData.botState,
                strategyData.marketExt,
                TradeActionType.AddLiqFromYt
            )
        );
        ApproxParams memory mockSwapParams = _getMockApproxParams();
        while (guessParams.guessMax > guessParams.guessMin + 1) {
            uint256 guess = guessParams.guessMin +
                (guessParams.guessMax - guessParams.guessMin) /
                2;
            (
                bool success,
                BotState memory botStateAfter,
                MarketExtState memory marketExtAfter
            ) = previewAction(strategyData, TradeActionType.AddLiqFromYt, guess, mockSwapParams);

            if (!success) {
                guessParams.guessMax = guess - 1;
                continue;
            }

            (, , , ytPtRatioAfter) = _calcBotExtStats(botStateAfter, marketExtAfter);
            if (ytPtRatioAfter >= strategyData.specs.minYtPtRatio) {
                guessParams.guessMin = guess;
                maxYtToAddLiq = strategyData.botState.ytBalance - botStateAfter.ytBalance;
            } else {
                guessParams.guessMax = guess - 1;
            }
        }
        return maxYtToAddLiq;
    }

    /// @dev Does not modify params, structs are cloned before simulation
    function previewAction(
        StrategyData memory strategyData,
        TradeActionType action,
        uint256 botParam,
        ApproxParams memory intParams
    ) public pure returns (bool success, BotState memory bot, MarketExtState memory marketExt) {
        bot = strategyData.botState.clone();
        marketExt = strategyData.marketExt.clone();

        if (action == TradeActionType.AddLiqFromYt) {
            success = bot.addLiqFromYt(marketExt, botParam);
        } else if (action == TradeActionType.RemoveLiqToYt) {
            success = bot.removeLiqToYt(marketExt, botParam, intParams);
        } else {
            success = false;
        }
    }

    /// @dev Gives a weak upper bound so that MarketExtLib's simulation doesn't revert
    function _weakUpperBound(
        BotState memory bot,
        MarketExtState memory marketExt,
        TradeActionType action
    ) internal pure override returns (uint256) {
        if (action == TradeActionType.AddLiqFromYt) {
            return marketExt.calcMaxPtOut();
        } else {
            return bot.lpBalance;
        }
    }

    // To compare the outcome impliedYield with tradingParams
    // For addLiqFromYt, there is an additional check for yt/pt ratio, which is rebalanceAdditionalCheck
    function _getTradeActionResult(
        TradeParams memory params,
        uint256 botParam,
        uint256 rebalanceAdditionalCheck,
        uint256 eps,
        ApproxParams memory intParams
    ) internal pure override returns (TradeActionResult) {
        (
            bool success,
            BotState memory newBotState,
            MarketExtState memory marketExt
        ) = previewAction(params.strategyData, params.action, botParam, intParams);

        if (!success) return TradeActionResult.FAIL_OR_TARGET_EXCEED;

        uint256 iy = marketExt.impliedYield();
        if (params.action == TradeActionType.AddLiqFromYt) {
            uint256 netYtSwapped = params.strategyData.botState.ytBalance - newBotState.ytBalance;

            if (netYtSwapped > rebalanceAdditionalCheck) {
                return TradeActionResult.FAIL_OR_TARGET_EXCEED;
            }
            if (Math.isAGreaterApproxB(iy, params.targetIy, eps)) {
                return TradeActionResult.SUCCESS;
            } else {
                if (iy < params.targetIy) return TradeActionResult.FAIL_OR_TARGET_EXCEED;
                else return TradeActionResult.TARGET_NOT_REACHED;
            }
        } else {
            if (Math.isASmallerApproxB(iy, params.targetIy, eps)) {
                return TradeActionResult.SUCCESS;
            } else {
                if (iy > params.targetIy) return TradeActionResult.FAIL_OR_TARGET_EXCEED;
                else return TradeActionResult.TARGET_NOT_REACHED;
            }
        }
    }

    function _calcRemoveRebalance(
        StrategyData memory strategyData,
        uint256 tvl
    ) internal pure returns (RebalanceType rebalanceType, uint256 amountIn, uint256 amountOut) {
        uint256 totalSyRequired = tvl.mulDown(strategyData.specs.targetSyRatio) -
            strategyData.botState.syBalance;

        if (strategyData.botState.lpBalance > DUST_AMOUNT) {
            uint256 totalLiquidatedSy;
            uint256 proportion = Math.ONE; // proportion of lp used to achieve totalLiquidatedSy
            if (strategyData.botState.ytBalance < DUST_AMOUNT) {
                // In this case, we only do an approximation on amount of LP to liquidate
                // by swapping PT proportionally. As PT's swapping price impact is not as large
                // as YT
                rebalanceType = RebalanceType.LiquidateLp;
                totalLiquidatedSy = _calcLiquidateLpOut(
                    strategyData,
                    strategyData.botState.lpBalance
                );
            } else {
                rebalanceType = RebalanceType.RemoveLpAndYt;
                (totalLiquidatedSy, proportion) = _calcRemoveZpiOut(strategyData);
            }

            amountOut = Math.min(totalLiquidatedSy, totalSyRequired);
            amountIn =
                (strategyData.botState.lpBalance.mulDown(proportion) * amountOut) /
                totalLiquidatedSy;

            if (rebalanceType == RebalanceType.LiquidateLp) {
                // Recalculate amountOut in case of liquidating lp, since swapping pt to sy is not linear
                amountOut = _calcLiquidateLpOut(strategyData, amountIn);
            }
        } else if (strategyData.botState.ytBalance > DUST_AMOUNT) {
            // Position now should only consist of SY & YT
            uint256 syFromYT = strategyData.marketExt.clone().swapYtToSy(
                strategyData.botState.ytBalance
            );

            rebalanceType = RebalanceType.SellYt;
            amountIn = (totalSyRequired * strategyData.botState.ytBalance) / syFromYT;
            amountOut = strategyData.marketExt.clone().swapYtToSy(amountIn);
        }
    }

    function _calcLiquidateLpOut(
        StrategyData memory strategyData,
        uint256 netLpIn
    ) private pure returns (uint256 amountSyOut) {
        MarketExtState memory marketExt = strategyData.marketExt.clone();
        (int256 syFromLp, int256 ptFromLp) = marketExt.state.removeLiquidityCore(netLpIn.Int());
        return syFromLp.Uint() + marketExt.swapPtToSy(ptFromLp.Uint());
    }

    function _calcRemoveZpiOut(
        StrategyData memory strategyData
    ) private pure returns (uint256 amountSyOut, uint256 proportion) {
        MarketExtState memory marketExt = strategyData.marketExt.clone();
        (int256 syFromLp, int256 ptFromLp) = marketExt.state.removeLiquidityCore(
            strategyData.botState.lpBalance.Int()
        );

        proportion = Math.min(strategyData.botState.ytBalance, ptFromLp.Uint()).divDown(
            ptFromLp.Uint()
        );

        amountSyOut = (syFromLp.Uint() + marketExt.index.assetToSyUp(ptFromLp.Uint())).mulDown(
            proportion
        );
    }
}

