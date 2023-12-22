// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./BotSimulationLib.sol";
import "./Errors.sol";
import "./IBotDecisionHelper.sol";

contract BotDecisionHelper is IBotDecisionHelper {
    using MarketExtLib for MarketExtState;
    using MarketExtLib for ApproxParams;
    using MarketMathCore for MarketState;
    using MarketApproxPtInLib for MarketState;
    using BotSimulationLib for BotState;
    using PYIndexLib for PYIndex;
    using Math for uint256;

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
        BotState memory bot,
        MarketExtState memory marketExt,
        LongTradingSpecs memory specs,
        ActionType action,
        ApproxParams memory botParams,
        ApproxParams memory intParams
    ) public pure returns (uint256, RebalanceResult) {
        RebalanceDetails memory rebalance = RebalanceDetails(bot, marketExt, specs, action);

        if (botParams.guessOffchain != 0) {
            uint256 guessOffchainMinusDelta = botParams.guessOffchain.mulDown(
                Math.ONE - botParams.eps
            );
            if (
                _rebalanceResult(rebalance, botParams.guessOffchain, intParams) ==
                RebalanceResult.TARGET_REACHED &&
                _rebalanceResult(rebalance, guessOffchainMinusDelta, intParams) ==
                RebalanceResult.TARGET_NOT_REACHED
            ) return (botParams.guessOffchain, RebalanceResult.TARGET_REACHED);
        }

        {
            uint256 guessUpperBound = _weakUpperBound(bot, marketExt, action);
            if (botParams.guessMax > guessUpperBound) botParams.guessMax = guessUpperBound;
            if (botParams.guessMin > botParams.guessMax)
                revert Errors.BotBinarySearchInvalidRange(
                    uint256(action),
                    botParams.guessMin,
                    botParams.guessMax
                );

            if (
                _rebalanceResult(rebalance, botParams.guessMax, intParams) ==
                RebalanceResult.TARGET_NOT_REACHED
            ) return (botParams.guessMax, RebalanceResult.TARGET_NOT_REACHED);
        }

        {
            RebalanceResult guessMinResult = _rebalanceResult(
                rebalance,
                botParams.guessMin,
                intParams
            );
            if (guessMinResult == RebalanceResult.FAIL)
                revert Errors.BotBinarySearchGuessMinInvalid(uint256(action), botParams.guessMin);
            if (guessMinResult == RebalanceResult.TARGET_REACHED)
                return (botParams.guessMin, RebalanceResult.TARGET_REACHED);
        }

        for (uint256 iter = 0; iter < botParams.maxIteration; ++iter) {
            uint256 guess = botParams.guessMin + (botParams.guessMax - botParams.guessMin) / 2;

            if (
                _rebalanceResult(rebalance, guess, intParams) == RebalanceResult.TARGET_NOT_REACHED
            ) {
                botParams.guessMin = guess;
            } else {
                botParams.guessMax = guess;
            }

            if (Math.isASmallerApproxB(botParams.guessMin, botParams.guessMax, botParams.eps)) {
                if (
                    _rebalanceResult(rebalance, botParams.guessMin, intParams) ==
                    RebalanceResult.FAIL
                )
                    return (
                        botParams.guessMin,
                        _rebalanceResult(rebalance, botParams.guessMin, intParams)
                    );

                return (
                    botParams.guessMax,
                    _rebalanceResult(rebalance, botParams.guessMax, intParams)
                );
            }
        }

        revert Errors.BotBinarySearchFail();
    }

    /**
     * Given the rebalancing action and its `botParam`, binary search for the optimal internal
     * parameter `intParam` for the internal action's approximation (e.g. for router's swap)
     */
    function searchForIntParam(
        MarketExtState memory marketExt,
        ActionType action,
        uint256 botParam,
        ApproxParams memory intParams
    ) public pure returns (uint256) {
        if (action == ActionType.RemoveLiqToYt) {
            (, uint256 totalPtToSwap) = marketExt.clone().removeLiqToYt(botParam, intParams);
            return totalPtToSwap;
        } else {
            return 0;
        }
    }

    function strategyState(
        BotState memory bot,
        MarketExtState memory marketExt,
        LongTradingSpecs memory specs
    ) public pure returns (StrategyState memory currentState) {
        (, uint256 iy, uint256 currentSyRatio, uint256 currentYtPtRatio) = botExtStats(
            bot,
            marketExt
        );

        if (iy < specs.lowerIyLimit) {
            currentState.iyFlag = StrategyFlag.TOO_LOW;
        } else if (specs.upperIyLimit < iy && currentYtPtRatio > specs.ytPtRatioLimit) {
            currentState.iyFlag = StrategyFlag.TOO_HIGH;
        } else {
            currentState.iyFlag = StrategyFlag.GOOD;
        }

        if (currentSyRatio > specs.floatingSyRatioLimit) {
            currentState.syRatioFlag = StrategyFlag.TOO_HIGH;
        } else {
            currentState.syRatioFlag = StrategyFlag.GOOD;
        }
    }

    function actionToTake(
        BotState memory botState,
        StrategyState memory currentState
    ) public pure returns (ActionType) {
        if (currentState.iyFlag == StrategyFlag.TOO_LOW) {
            if (currentState.syRatioFlag == StrategyFlag.TOO_HIGH) {
                if (botState.syBalance == 0) return ActionType.NONE;
                return ActionType.SwapSyToYt;
            } else {
                if (botState.lpBalance == 0) return ActionType.NONE;
                return ActionType.RemoveLiqToYt;
            }
        } else if (currentState.iyFlag == StrategyFlag.GOOD) {
            if (currentState.syRatioFlag == StrategyFlag.TOO_HIGH) {
                if (botState.syBalance == 0) return ActionType.NONE;
                return ActionType.AddLiqKeepYt;
            } else {
                return ActionType.NONE;
            }
        } else {
            if (currentState.syRatioFlag == StrategyFlag.TOO_HIGH) {
                if (botState.syBalance == 0) return ActionType.NONE;
                return ActionType.AddLiqFromSy;
            } else {
                if (botState.ytBalance == 0) return ActionType.NONE;
                return ActionType.AddLiqFromYt;
            }
        }
    }

    /// @dev Does not modify params, structs are cloned before simulation
    function previewAction(
        BotState memory botData,
        MarketExtState memory marketExtData,
        ActionType action,
        uint256 botParam,
        ApproxParams memory swapApproxParams
    ) public pure returns (bool success, BotState memory bot, MarketExtState memory marketExt) {
        bot = botData.clone();
        marketExt = marketExtData.clone();

        if (action == ActionType.SwapSyToYt) {
            success = bot.swapSyToYt(marketExt, botParam);
        } else if (action == ActionType.AddLiqKeepYt) {
            success = bot.addLiqKeepYt(marketExt, botParam);
        } else if (action == ActionType.AddLiqFromSy) {
            success = bot.addLiqFromSy(marketExt, botParam);
        } else if (action == ActionType.AddLiqFromYt) {
            success = bot.addLiqFromYt(marketExt, botParam);
        } else if (action == ActionType.RemoveLiqToYt) {
            success = bot.removeLiqToYt(marketExt, botParam, swapApproxParams);
        } else {
            success = false;
        }
    }

    function botExtStats(
        BotState memory bot,
        MarketExtState memory marketExt
    )
        public
        pure
        returns (uint256 tvlInSy, uint256 iy, uint256 currentSyRatio, uint256 currentYtPtRatio)
    {
        tvlInSy = bot.tvlInSy(marketExt);

        iy = marketExt.impliedYield();

        currentSyRatio = bot.syBalance.divDown(tvlInSy);

        (, uint256 ptInLp) = marketExt.clone().removeLiqDual(bot.lpBalance);
        currentYtPtRatio = (ptInLp == 0 ? type(uint256).max : bot.ytBalance.divDown(ptInLp));
    }

    /// @dev Gives a weak upper bound so that MarketExtLib's simulation doesn't revert
    function _weakUpperBound(
        BotState memory bot,
        MarketExtState memory marketExt,
        ActionType action
    ) private pure returns (uint256) {
        if (action == ActionType.SwapSyToYt) {
            return marketExt.calcMaxPtIn();
        } else if (action == ActionType.AddLiqKeepYt) {
            return bot.syBalance;
        } else if (action == ActionType.AddLiqFromSy) {
            return marketExt.calcMaxPtOut();
        } else if (action == ActionType.AddLiqFromYt) {
            return marketExt.calcMaxPtOut();
        } else if (action == ActionType.RemoveLiqToYt) {
            return bot.lpBalance;
        } else {
            return 0;
        }
    }

    function _rebalanceResult(
        RebalanceDetails memory rebalance,
        uint256 botParam,
        ApproxParams memory intParams
    ) private pure returns (RebalanceResult) {
        (bool success, BotState memory bot, MarketExtState memory marketExt) = previewAction(
            rebalance.bot,
            rebalance.marketExt,
            rebalance.action,
            botParam,
            intParams
        );

        if (!success) return RebalanceResult.FAIL;
        if (_reachedTarget(bot, marketExt, rebalance.specs, rebalance.action)) {
            return RebalanceResult.TARGET_REACHED;
        }
        return RebalanceResult.TARGET_NOT_REACHED;
    }

    function _reachedTarget(
        BotState memory bot,
        MarketExtState memory marketExt,
        LongTradingSpecs memory specs,
        ActionType action
    ) private pure returns (bool) {
        uint256 targetIy = (specs.lowerIyLimit + specs.upperIyLimit) / 2;

        (, uint256 iy, uint256 currentSyRatio, uint256 currentYtPtRatio) = botExtStats(
            bot,
            marketExt
        );

        if (action == ActionType.SwapSyToYt) {
            return iy >= targetIy || currentSyRatio <= specs.floatingSyRatioTarget;
        } else if (action == ActionType.AddLiqKeepYt) {
            return currentSyRatio <= specs.floatingSyRatioTarget;
        } else if (action == ActionType.AddLiqFromSy) {
            return
                iy <= targetIy ||
                currentSyRatio <= specs.floatingSyRatioTarget ||
                currentYtPtRatio <= specs.ytPtRatioTarget;
        } else if (action == ActionType.AddLiqFromYt) {
            return iy <= targetIy || currentYtPtRatio <= specs.ytPtRatioTarget;
        } else if (action == ActionType.RemoveLiqToYt) {
            return iy >= targetIy;
        } else {
            return true;
        }
    }
}

