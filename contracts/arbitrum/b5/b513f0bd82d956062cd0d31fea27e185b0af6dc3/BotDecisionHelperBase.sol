// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./BotSimulationLib.sol";
import "./Errors.sol";
import "./SpecSegmentLib.sol";
import "./IBotDecisionHelper.sol";
import "./ITradingBotBase.sol";

abstract contract BotDecisionHelperBase is IBotDecisionHelper {
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

    uint256 public constant MINIMAL_EPS = 100000000000000;
    uint256 public constant INF = type(uint256).max;

    function getBotPosition(
        address botAddress
    )
        public
        view
        returns (
            StrategyData memory strategyData,
            uint256 tvlInSy,
            uint256 iy,
            uint256 floatingSyRatio,
            uint256 currentYtPtRatio
        )
    {
        strategyData = ITradingBotBase(botAddress).readStrategyData();
        (tvlInSy, iy, floatingSyRatio, currentYtPtRatio) = _calcBotExtStats(
            strategyData.botState,
            strategyData.marketExt
        );
    }

    /**
     * Return the current bin corresponds to market state
     */
    function getCurrentBin(StrategyData memory strategyData) public pure returns (int256) {
        return
            _getCurrentBin(
                strategyData.botState,
                strategyData.specs,
                strategyData.marketExt.impliedYield()
            );
    }

    /**
     * Binary search for the smallest parameter `botParam` for the corresponding rebalancing action
     * such that the bot reaches desired target, otherwise give the largest `botParam` possible
     * that action doesn't revert.
     * 
     * Function target:
     * - currentBin < 0: Remove LP to YT until targetImpliedYield is reached
     * - currentBin > 0: Add LP from YT until targetImpliedYield is reached or YT/PT rate reached its minimum in specs
     *
     * @param strategyData StrategyData of the bot
     * @param action Action to take, from which target is derived
     * @param targetIy Target implied yield for the bot to achieve
     * @param rebalanceAdditionalCheck Additional check for rebalance (used in yt / pt rate for AddLiqFromYt)
     * @param botParams ApproxParams for `botParam`
     * @param intParams ApproxParams for internal action's approximation (e.g. for router's swap)
     *
     * For `botParams`, eps = the precision such that slightly lower
     * (param = (return value) * (1 - eps)) does not reach target
     *
     * - Returns `botParams.guessOffchain` if it reaches target
     * - Returns `botParams.guessMax` if it is valid or does not reach target
     * - Otherwise, binary search for `guess` such that it reaches target, and slightly lower does
     * not
     *
     */
    function searchForBotParam(
        StrategyData memory strategyData,
        TradeActionType action,
        uint256 targetIy,
        uint256 rebalanceAdditionalCheck,
        ApproxParams memory botParams,
        ApproxParams memory intParams
    ) public pure returns (uint256) {
        TradeParams memory params = TradeParams(strategyData, action, targetIy);
        if (botParams.guessOffchain != 0) {
            // guessoffchain is good
            if (
                _getTradeActionResult(
                    params,
                    botParams.guessOffchain,
                    rebalanceAdditionalCheck,
                    botParams.eps,
                    intParams
                ) == TradeActionResult.SUCCESS
            ) return botParams.guessOffchain;
        }

        {
            // check for invalid range
            uint256 guessUpperBound = _weakUpperBound(
                strategyData.botState,
                strategyData.marketExt,
                action
            );
            if (botParams.guessMax > guessUpperBound) botParams.guessMax = guessUpperBound;
            if (botParams.guessMin > botParams.guessMax)
                revert Errors.BotBinarySearchInvalidRange(
                    uint256(action),
                    botParams.guessMin,
                    botParams.guessMax
                );
        }

        {
            // if botParams.guessMax is either success or unsatisfied (target_not_reached), then we'll just go with it
            if (
                _getTradeActionResult(
                    params,
                    botParams.guessMax,
                    rebalanceAdditionalCheck,
                    botParams.eps,
                    intParams
                ) != TradeActionResult.FAIL_OR_TARGET_EXCEED
            ) {
                return botParams.guessMax;
            }
        }

        for (uint256 iter = 0; iter < botParams.maxIteration; ++iter) {
            uint256 guess = botParams.guessMin + (botParams.guessMax - botParams.guessMin) / 2;

            TradeActionResult res = _getTradeActionResult(
                params,
                guess,
                rebalanceAdditionalCheck,
                botParams.eps,
                intParams
            );

            if (res == TradeActionResult.SUCCESS) {
                return guess;
            } else if (res == TradeActionResult.TARGET_NOT_REACHED) {
                botParams.guessMin = guess;
            } else {
                botParams.guessMax = guess;
            }
        }

        if (botParams.guessMin != 0) {
            return botParams.guessMin;
        }

        revert Errors.BotBinarySearchFail();
    }

    function _calcBotExtStats(
        BotState memory botState,
        MarketExtState memory marketExt
    )
        internal
        pure
        returns (uint256 tvlInSy, uint256 iy, uint256 floatingSyRatio, uint256 currentYtPtRatio)
    {
        tvlInSy = botState.tvlInSy(marketExt);
        iy = marketExt.impliedYield();
        floatingSyRatio = botState.syBalance.divDown(tvlInSy);
        (, uint256 ptInLp) = marketExt.clone().removeLiqDual(botState.lpBalance);

        uint256 totalPt = ptInLp + botState.ptBalance;

        if (totalPt != 0) {
            currentYtPtRatio = botState.ytBalance.divDown(totalPt);
        } else {
            if (botState.ytBalance == 0) {
                currentYtPtRatio = 0;
            } else {
                currentYtPtRatio = type(uint256).max;
            }
        }
    }

    function _getMockApproxParamsWithGuessMax(
        uint256 guessMax
    ) internal pure returns (ApproxParams memory) {
        return ApproxParams(1, guessMax, 0, 256, MINIMAL_EPS);
    }

    function _getMockApproxParams() internal pure returns (ApproxParams memory) {
        return ApproxParams(1, INF, 0, 256, MINIMAL_EPS);
    }

    function _getCurrentBin(
        BotState memory botState,
        TradingSpecs memory specs,
        uint256 iy
    ) internal pure returns (int256) {
        return specs.getBinIdForIy(botState, iy);
    }

    function _getTargetImpliedYieldForBin(
        BotState memory botState,
        TradingSpecs memory specs,
        int256 binId
    ) internal pure returns (uint256) {
        assert(binId != 0); // No action should be taken

        uint256 segId = SpecSegmentLib.convertBinIdToSegId(botState, binId);

        if (binId < 0) {
            return specs.getMidIyOfSeg(segId + 1);
        } else {
            return specs.getMidIyOfSeg(segId - 1);
        }
    }

    function _weakUpperBound(
        BotState memory bot,
        MarketExtState memory marketExt,
        TradeActionType action
    ) internal pure virtual returns (uint256);

    function _getTradeActionResult(
        TradeParams memory rebalance,
        uint256 botParam,
        uint256 rebalanceAdditionalCheck,
        uint256 eps,
        ApproxParams memory intParams
    ) internal pure virtual returns (TradeActionResult);

    /**
     * Calculate (amount * ((1+currentBins/buyBins) ^ (currentBins/buyBins) - 1)
     * @param amount max amount of token to perform the action
     * @param currentBin current bin value
     * @param buyBins number of buy bins in bot state
     * @param numOfBins number of bins (defined by specs)
     */
    function _calcTradeActionMaxAmount(
        uint256 amount,
        int256 currentBin,
        uint256 buyBins,
        uint256 numOfBins
    ) internal pure returns (uint256) {
        assert(currentBin != 0);
        uint256 pressureDenom = currentBin < 0 ? buyBins : numOfBins * 2 - buyBins;
        uint256 actionPressure = (currentBin.abs() * Math.ONE) / pressureDenom;
        uint256 proportion = (Math.ONE + actionPressure).pow(actionPressure) - Math.ONE;
        return amount.mulDown(proportion);
    }

    function _calcSyAmountForZPI(
        MarketExtState memory marketExt,
        uint256 tvl,
        uint256 floatingSyRatio,
        uint256 targetSyRatio
    ) internal pure returns (uint256 amountSyIn, uint256 amountLpOut, uint256 amountYtOut) {
        amountSyIn = tvl.mulDown(floatingSyRatio - targetSyRatio);
        (amountLpOut, amountYtOut) = marketExt.addLiqKeepYt(amountSyIn);
    }
}

