// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./BotSimulationLib.sol";
import "./Errors.sol";
import "./SpecSegmentLib.sol";
import "./BotDecisionHelperBase.sol";
import "./IShortYieldDecisionHelper.sol";
import "./IShortYieldTradingBot.sol";

contract ShortYieldDecisionHelper is BotDecisionHelperBase, IShortYieldDecisionHelper {
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

    // We dont care about AddLiqKeepYt here
    function getActionDetails(address botAddress) public returns (ActionToTakeResult memory res) {
        StrategyData memory strategyData = IShortYieldTradingBot(botAddress).readStrategyData();
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

        if (res.currentBin < 0) {
            res.action = ActionType.SwapPtForYt;
            uint256 maxPtToSwap = _searchMaxPtToSwap(strategyData);
            maxAmountForAction = _calcMaxAmountForAction(
                maxPtToSwap,
                res.currentBin,
                strategyData.botState.buyBins,
                strategyData.specs.numOfBins
            );
        } else {
            res.action = ActionType.SwapYtForPt;
            maxAmountForAction = _calcMaxAmountForAction(
                strategyData.botState.ytBalance,
                res.currentBin,
                strategyData.botState.buyBins,
                strategyData.specs.numOfBins
            );
        }

        if (maxAmountForAction == 0) {
            return res;
        }

        res.guessBotParams = searchForBotParam(
            strategyData,
            res.action,
            res.targetIy,
            0,
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
     * Given the rebalancing action and its `botParam`, binary search for the optimal internal
     * parameter `intParam` for the internal action's approximation (e.g. for router's swap)
     */
    function _calcAmountOutAndIntParams(
        MarketExtState memory marketExt,
        ActionType action,
        uint256 botParam
    ) public pure returns (uint256 amountOut, uint256 intParams) {
        if (action == ActionType.SwapPtForYt) {
            (amountOut, intParams) = marketExt.clone().swapPtToYt(
                botParam,
                _getMockApproxParams()
            );
        } else {
            (amountOut, intParams) = marketExt.clone().swapYtToPt(
                botParam,
                _getMockApproxParams()
            );
        }
    }

    function _searchMaxPtToSwap(StrategyData memory strategyData) internal pure returns (uint256) {
        (, , , uint256 ytPtRatio) = _calcBotExtStats(
            strategyData.botState,
            strategyData.marketExt
        );
        if (ytPtRatio > strategyData.specs.targetYtPtRatio) {
            return 0;
        }

        ApproxParams memory guessParams = _getMockApproxParamsWithGuessMax(
            strategyData.botState.ptBalance
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
            ) = previewAction(strategyData, ActionType.SwapPtForYt, guess, mockSwapParams);

            if (!success) {
                guessParams.guessMax = guess - 1;
                continue;
            }

            (, , , uint256 ytPtRatioAfter) = _calcBotExtStats(botStateAfter, marketExtAfter);
            if (ytPtRatioAfter <= strategyData.specs.targetYtPtRatio) {
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

        if (action == ActionType.SwapPtForYt) {
            success = bot.swapPtToYt(marketExt, botParam, intParams);
        } else if (action == ActionType.SwapYtForPt) {
            success = bot.swapYtToPt(marketExt, botParam, intParams);
        } else {
            success = false;
        }
    }

    /// @dev Gives a weak upper bound so that MarketExtLib's simulation doesn't revert
    function _weakUpperBound(
        BotState memory bot,
        MarketExtState memory,
        ActionType action
    ) internal pure override returns (uint256) {
        if (action == ActionType.SwapPtForYt) {
            return bot.ptBalance;
        } else {
            return bot.ytBalance;
        }
    }

    function _rebalanceResult(
        RebalanceDetails memory rebalance,
        uint256 botParam,
        uint256,
        uint256 eps,
        ApproxParams memory intParams
    ) internal pure override returns (RebalanceResult) {
        (bool success, , MarketExtState memory marketExt) = previewAction(
            rebalance.strategyData,
            rebalance.action,
            botParam,
            intParams
        );

        if (!success) return RebalanceResult.FAIL_OR_TARGET_EXCEED;

        uint256 iy = marketExt.impliedYield();
        if (rebalance.action == ActionType.SwapPtForYt) {
            if (iy > rebalance.targetIy) return RebalanceResult.FAIL_OR_TARGET_EXCEED;
        } else {
            if (iy < rebalance.targetIy) return RebalanceResult.FAIL_OR_TARGET_EXCEED;
        }

        if (Math.isAApproxB(iy, rebalance.targetIy, eps)) return RebalanceResult.SUCCESS;
        else return RebalanceResult.TARGET_NOT_REACHED;
    }
}

