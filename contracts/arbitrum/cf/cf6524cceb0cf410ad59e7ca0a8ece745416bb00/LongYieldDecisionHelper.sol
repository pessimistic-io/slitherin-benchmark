// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./BotSimulationLib.sol";
import "./Errors.sol";
import "./SpecSegmentLib.sol";
import "./IBotDecisionHelper.sol";
import "./ILongYieldTradingBot.sol";

contract LongYieldDecisionHelper is IBotDecisionHelper {
    using MarketExtLib for MarketExtState;
    using MarketExtLib for ApproxParams;
    using MarketMathCore for MarketState;
    using MarketApproxPtInLib for MarketState;
    using BotSimulationLib for BotState;
    using PYIndexLib for PYIndex;
    using Math for uint256;
    using Math for int256;
    using LogExpMath for uint256;
    using SpecSegmentLib for LongTradingSpecs;

    uint256 public constant MINIMAL_EPS = 100000000000000;
    uint256 public constant INF = type(uint256).max;

    function getAvailableZpiAmount(address botAddress) public returns (uint256 amountSyToZpi) {
        StrategyData memory strategyData = ILongYieldTradingBot(botAddress).readStrategyData();
        (uint256 tvlInSy, , uint256 syRatio, ) = _calcBotExtStats(
            strategyData.botState,
            strategyData.marketExt
        );
        if (syRatio < strategyData.specs.maxSyRatio) return 0;

        return strategyData.botState.syBalance - tvlInSy.mulDown(strategyData.specs.targetSyRatio);
    }

    /**
     * Return the current bin corresponds to market state
     *
     * Negative value -> buy bin, b_abs(currentBin)
     * Positive value -> sell bin, s_abs(currentBin)
     * Zero -> Do nothing
     */
    function getCurrentBin(StrategyData memory strategyData) public view returns (int256) {
        return
            _getCurrentBin(
                strategyData.botState,
                strategyData.specs,
                strategyData.marketExt.impliedYield()
            );
    }

    // We dont care about AddLiqKeepYt here
    function getActionDetails(address botAddress) public returns (ActionToTakeResult memory res) {
        StrategyData memory strategyData = ILongYieldTradingBot(botAddress).readStrategyData();
        uint256 iy = strategyData.marketExt.impliedYield();

        res.currentBin = _getCurrentBin(strategyData.botState, strategyData.specs, iy);
        if (res.currentBin == 0) {
            res.action = ActionType.NONE;
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
            res.action = ActionType.RemoveLiqToYt;
            maxAmountForAction = _calcMaxAmountForAction(
                strategyData.botState.lpBalance,
                res.currentBin,
                strategyData.botState.buyBins,
                strategyData.specs.numOfBins
            );

            if (maxAmountForAction == 0) {
                return res;
            }
        } else {
            res.action = ActionType.AddLiqFromYt;
            uint256 maxYtToAddLiq = _searchMaxYtToAddLiq(strategyData);

            rebalanceAdditionalCheck = _calcMaxAmountForAction(
                maxYtToAddLiq,
                res.currentBin,
                strategyData.botState.buyBins,
                strategyData.specs.numOfBins
            );

            if (rebalanceAdditionalCheck == 0) {
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
        (res.amountOut, res.guessIntParams) = _calcAmountOutAndIntParams(
            strategyData.marketExt,
            res.action,
            res.guessBotParams
        );
    }

    /**
     * Binary search for the smallest parameter `botParam` for the corresponding rebalancing action
     * such that the bot reaches desired target, otherwise give the largest `botParam` possible
     * that action doesn't revert.
     *
     * @param action Action to take, from which target is derived
     * @param botParams ApproxParams for `botParam`
     * @param intParams ApproxParams for internal action's approximation (e.g. for router's swap)
     *
     * For `botParams`, eps = the precision such that slightly lower
     * (param = (return value) * (1 - eps)) does not reach target
     *
     * - Returns `botParams.guessOffchain` if it reaches target, and slightly lower does not
     * - Reverts if `botParams.guessMin` is invalid, or returns `botParams.guessMin` if reaches
     * target
     * - Returns `botParams.guessMax` if it is valid & does not reach target
     * - Otherwise, binary search for `guess` such that it reaches target, and slightly lower does
     * not
     *
     */
    function searchForBotParam(
        StrategyData memory strategyData,
        ActionType action,
        uint256 targetIy,
        uint256 rebalanceAdditionalCheck,
        ApproxParams memory botParams,
        ApproxParams memory intParams
    ) public pure returns (uint256) {
        RebalanceDetails memory rebalance = RebalanceDetails(strategyData, action, targetIy);
        if (botParams.guessOffchain != 0) {
            // guessoffchain is good
            if (
                _rebalanceResult(
                    rebalance,
                    botParams.guessOffchain,
                    rebalanceAdditionalCheck,
                    botParams.eps,
                    intParams
                ) == RebalanceResult.SUCCESS
            ) return botParams.guessOffchain;
        }

        {
            // invalid range
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
                _rebalanceResult(
                    rebalance,
                    botParams.guessMax,
                    rebalanceAdditionalCheck,
                    botParams.eps,
                    intParams
                ) != RebalanceResult.FAIL_OR_TARGET_EXCEED
            ) {
                return botParams.guessMax;
            }
        }

        for (uint256 iter = 0; iter < botParams.maxIteration; ++iter) {
            uint256 guess = botParams.guessMin + (botParams.guessMax - botParams.guessMin) / 2;

            RebalanceResult res = _rebalanceResult(
                rebalance,
                guess,
                rebalanceAdditionalCheck,
                botParams.eps,
                intParams
            );

            if (res == RebalanceResult.SUCCESS) {
                return guess;
            } else if (res == RebalanceResult.TARGET_NOT_REACHED) {
                botParams.guessMin = guess;
            } else {
                botParams.guessMax = guess;
            }
        }

        revert Errors.BotBinarySearchFail();
    }

    /**
     * Given the rebalancing action and its `botParam`, binary search for the optimal internal
     * parameter `intParam` for the internal action's approximation (e.g. for router's swap)
     */
    function _calcAmountOutAndIntParams(
        MarketExtState memory marketExt,
        ActionType action,
        uint256 botParam
    ) public pure returns (uint256 amountOut, uint256 intParams) {
        if (action == ActionType.RemoveLiqToYt) {
            (amountOut, intParams) = marketExt.clone().removeLiqToYt(
                botParam,
                _getMockApproxParams()
            );
        } else {
            (amountOut, ) = marketExt.clone().addLiqFromYt(botParam);
        }
    }

    function _searchMaxYtToAddLiq(
        StrategyData memory strategyData
    ) internal pure returns (uint256) {
        (, , , uint256 ytPtRatioAfter) = _calcBotExtStats(
            strategyData.botState,
            strategyData.marketExt
        );
        if (ytPtRatioAfter < strategyData.specs.minYtPtRatio) {
            return 0;
        }

        ApproxParams memory guessParams = _getMockApproxParamsWithGuessMax(
            strategyData.botState.ytBalance
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
            ) = previewAction(strategyData, ActionType.AddLiqFromYt, guess, mockSwapParams);

            if (!success) {
                guessParams.guessMax = guess - 1;
                continue;
            }

            (, , , ytPtRatioAfter) = _calcBotExtStats(botStateAfter, marketExtAfter);
            if (ytPtRatioAfter >= strategyData.specs.minYtPtRatio) {
                guessParams.guessMin = guess;
            } else {
                guessParams.guessMax = guess - 1;
            }
        }
        return guessParams.guessMin;
    }

    /// @dev Does not modify params, structs are cloned before simulation
    function previewAction(
        StrategyData memory strategyData,
        ActionType action,
        uint256 botParam,
        ApproxParams memory intParams
    ) public pure returns (bool success, BotState memory bot, MarketExtState memory marketExt) {
        bot = strategyData.botState.clone();
        marketExt = strategyData.marketExt.clone();

        if (action == ActionType.AddLiqFromYt) {
            success = bot.addLiqFromYt(marketExt, botParam);
        } else if (action == ActionType.RemoveLiqToYt) {
            success = bot.removeLiqToYt(marketExt, botParam, intParams);
        } else {
            success = false;
        }
    }

    function _calcBotExtStats(
        BotState memory botState,
        MarketExtState memory marketExt
    )
        internal
        pure
        returns (uint256 tvlInSy, uint256 iy, uint256 currentSyRatio, uint256 currentYtPtRatio)
    {
        tvlInSy = botState.tvlInSy(marketExt);
        iy = marketExt.impliedYield();
        currentSyRatio = botState.syBalance.divDown(tvlInSy);
        (, uint256 ptInLp) = marketExt.clone().removeLiqDual(botState.lpBalance);
        currentYtPtRatio = (ptInLp == 0 ? type(uint256).max : botState.ytBalance.divDown(ptInLp));
    }

    function botExtStats(
        StrategyData memory strategyData
    )
        external
        pure
        returns (uint256 tvlInSy, uint256 iy, uint256 currentSyRatio, uint256 currentYtPtRatio)
    {
        return _calcBotExtStats(strategyData.botState, strategyData.marketExt);
    }

    /// @dev Gives a weak upper bound so that MarketExtLib's simulation doesn't revert
    function _weakUpperBound(
        BotState memory bot,
        MarketExtState memory marketExt,
        ActionType action
    ) private pure returns (uint256) {
        if (action == ActionType.AddLiqFromYt) {
            return marketExt.calcMaxPtOut();
        } else {
            return bot.lpBalance;
        }
    }

    function _rebalanceResult(
        RebalanceDetails memory rebalance,
        uint256 botParam,
        uint256 rebalanceAdditionalCheck,
        uint256 eps,
        ApproxParams memory intParams
    ) private pure returns (RebalanceResult) {
        (
            bool success,
            BotState memory newBotState,
            MarketExtState memory marketExt
        ) = previewAction(rebalance.strategyData, rebalance.action, botParam, intParams);

        if (!success) return RebalanceResult.FAIL_OR_TARGET_EXCEED;
        // return RebalanceResult.SUCCESS;

        uint256 iy = marketExt.impliedYield();
        if (rebalance.action == ActionType.AddLiqFromYt) {
            uint256 netYtSwapped = rebalance.strategyData.botState.ytBalance -
                newBotState.ytBalance;

            if (netYtSwapped > rebalanceAdditionalCheck) {
                return RebalanceResult.FAIL_OR_TARGET_EXCEED;
            }
            if (Math.isAGreaterApproxB(iy, rebalance.targetIy, eps)) {
                return RebalanceResult.SUCCESS;
            } else {
                if (iy < rebalance.targetIy) return RebalanceResult.FAIL_OR_TARGET_EXCEED;
                else return RebalanceResult.TARGET_NOT_REACHED;
            }
        } else {
            if (Math.isASmallerApproxB(iy, rebalance.targetIy, eps)) {
                return RebalanceResult.SUCCESS;
            } else {
                if (iy > rebalance.targetIy) return RebalanceResult.FAIL_OR_TARGET_EXCEED;
                else return RebalanceResult.TARGET_NOT_REACHED;
            }
        }
    }

    function _getCurrentBin(
        BotState memory botState,
        LongTradingSpecs memory specs,
        uint256 iy
    ) internal view returns (int256) {
        return specs.getBinIdForIy(botState, iy);
    }

    function _getTargetImpliedYieldForBin(
        BotState memory botState,
        LongTradingSpecs memory specs,
        int256 binId
    ) internal view returns (uint256) {
        assert(binId != 0); // No action should be taken

        uint256 segId = SpecSegmentLib.convertBinIdToSegId(botState, binId);

        if (binId < 0) {
            return specs.getMidIyOfSeg(segId + 1);
        } else {
            return specs.getMidIyOfSeg(segId - 1);
        }
    }

    function _calcMaxAmountForAction(
        uint256 amount,
        int256 currentBin,
        uint256 buyBins,
        uint256 numOfBins
    ) private pure returns (uint256) {
        assert(currentBin != 0);
        uint256 pressureDenom = currentBin < 0 ? buyBins : numOfBins * 2 - buyBins;
        uint256 actionPressure = (currentBin.abs() * Math.ONE) / pressureDenom;
        uint256 proportion = (Math.ONE + actionPressure).pow(actionPressure) - Math.ONE;
        return amount.mulDown(proportion);
    }

    function _getMockApproxParamsWithGuessMax(
        uint256 guessMax
    ) private pure returns (ApproxParams memory) {
        return ApproxParams(1, guessMax, 0, 256, MINIMAL_EPS);
    }

    function _getMockApproxParams() private pure returns (ApproxParams memory) {
        return ApproxParams(1, INF, 0, 256, MINIMAL_EPS);
    }
}

