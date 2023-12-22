// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./BotSimulationLib.sol";
import "./Errors.sol";

struct LongTradingSpecs {
    uint256 lowerIyLimit; // apeYtApy
    uint256 upperIyLimit; // sellYtApy
    uint256 floatingSyRatioLimit; // r
    uint256 ytPtRatioLimit; // ytPtRatio (x)
}

enum ActionType {
    SwapSyToYt, // Buy YT with SY
    AddLiqKeepYt, // ZPI Zap
    AddLiqFromSy, // Single sided LP
    AddLiqFromYt, // Sell YT for LP
    RemoveLiqToYt, // Zap out to YT,
    NONE
}

enum StrategyFlag {
    GOOD,
    TOO_LOW,
    TOO_HIGH
}

struct StrategyState {
    StrategyFlag iyFlag;
    StrategyFlag syRatioFlag;
}

contract BotDecisionLib {
    using MarketExtLib for MarketExtState;
    using MarketExtLib for ApproxParams;
    using BotSimulationLib for BotState;
    using Math for uint256;

    enum RebalanceResult {
        FAIL,
        OLD_STATE,
        NEW_STATE
    }

    struct RebalanceDetails {
        BotState bot;
        MarketExtState marketExt;
        LongTradingSpecs specs;
        ActionType action;
        StrategyState oldState;
    }

    /**
     * Finds the smallest paramater such that the bot reaches a new state, otherwise finds the
     * largest parameter possible that doesn't fail.
     *
     * @param botParams ApproxParams for this binary search function
     * @param oldState The initial StrategyState, to be moved away from
     * @param intParams ApproxParams for public action's approximation (e.g. for router's swap)
     * @dev For `botParams`, eps = the precision such that slightly lower
     * ((return value) * (1 - eps)) does not reach a new state
     *
     * - Returns `botParams.guessOffchain` if verifies that it reaches a new state,
     * and slightly lower does not reach a new state.
     * - Reverts if `botParams.guessMin` is invalid, or returns `botParams.guessMin` if reaches a
     * new state
     * - Returns `botParams.guessMax` if it is valid & does not reach a new state
     * - Otherwise, binary search for `guess` such that it reaches a new state, and slightly lower
     * does not reach a new state
     *
     */
    function binarySearchUntilSwitchState(
        BotState memory bot,
        MarketExtState memory marketExt,
        LongTradingSpecs memory specs,
        ActionType action,
        StrategyState memory oldState,
        ApproxParams memory botParams,
        ApproxParams memory intParams
    ) public pure returns (uint256) {
        RebalanceDetails memory rebalance = RebalanceDetails(
            bot,
            marketExt,
            specs,
            action,
            oldState
        );

        if (botParams.guessOffchain != 0) {
            uint256 guessOffchainMinusDelta = botParams.guessOffchain.mulDown(
                Math.ONE - botParams.eps
            );
            if (
                _rebalanceResult(rebalance, botParams.guessOffchain, intParams) ==
                RebalanceResult.NEW_STATE &&
                _rebalanceResult(rebalance, guessOffchainMinusDelta, intParams) ==
                RebalanceResult.OLD_STATE
            ) return botParams.guessOffchain;
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
                RebalanceResult.OLD_STATE
            ) return botParams.guessMax;
        }

        {
            RebalanceResult guessMinResult = _rebalanceResult(
                rebalance,
                botParams.guessMin,
                intParams
            );
            if (guessMinResult == RebalanceResult.FAIL)
                revert Errors.BotBinarySearchGuessMinInvalid(uint256(action), botParams.guessMin);
            if (guessMinResult == RebalanceResult.NEW_STATE) return botParams.guessMin;
        }

        for (uint256 iter = 0; iter < botParams.maxIteration; ++iter) {
            uint256 guess = botParams.guessMin + (botParams.guessMax - botParams.guessMin) / 2;

            if (_rebalanceResult(rebalance, guess, intParams) == RebalanceResult.OLD_STATE) {
                botParams.guessMin = guess;
            } else {
                botParams.guessMax = guess;
            }

            if (Math.isASmallerApproxB(botParams.guessMin, botParams.guessMax, botParams.eps)) {
                if (
                    _rebalanceResult(rebalance, botParams.guessMax, intParams) ==
                    RebalanceResult.FAIL
                ) return botParams.guessMin;

                return botParams.guessMax;
            }
        }

        revert Errors.BotBinarySearchFail();
    }

    function _rebalanceResult(
        RebalanceDetails memory rebalance,
        uint256 botParam,
        ApproxParams memory intParams
    ) private pure returns (RebalanceResult) {
        (bool success, StrategyState memory newState) = _stateAfterRebalance(
            rebalance,
            botParam,
            intParams
        );

        if (!success) return RebalanceResult.FAIL;
        if (_sameStrategyState(rebalance.oldState, newState)) return RebalanceResult.OLD_STATE;
        return RebalanceResult.NEW_STATE;
    }

    function _sameStrategyState(
        StrategyState memory initialState,
        StrategyState memory otherState
    ) private pure returns (bool) {
        return
            (initialState.iyFlag == otherState.iyFlag) &&
            (initialState.syRatioFlag == otherState.syRatioFlag);
    }

    function _stateAfterRebalance(
        RebalanceDetails memory rebalance,
        uint256 botParam,
        ApproxParams memory intParams
    ) private pure returns (bool success, StrategyState memory currentState) {
        BotState memory botClone = rebalance.bot.clone();
        MarketExtState memory marketExtClone = rebalance.marketExt.clone();

        if (rebalance.action == ActionType.SwapSyToYt) {
            success = botClone.swapSyToYt(marketExtClone, botParam);
        } else if (rebalance.action == ActionType.AddLiqKeepYt) {
            success = botClone.addLiqKeepYt(marketExtClone, botParam);
        } else if (rebalance.action == ActionType.AddLiqFromSy) {
            success = botClone.addLiqFromSy(marketExtClone, botParam);
        } else if (rebalance.action == ActionType.AddLiqFromYt) {
            success = botClone.addLiqFromYt(marketExtClone, botParam);
        } else if (rebalance.action == ActionType.RemoveLiqToYt) {
            success = botClone.removeLiqToYt(marketExtClone, botParam, intParams.clone());
        } else {
            success = false;
        }

        if (success) {
            currentState = strategyState(botClone, marketExtClone, rebalance.specs);
        }
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

    function strategyState(
        BotState memory bot,
        MarketExtState memory marketExt,
        LongTradingSpecs memory specs
    ) public pure returns (StrategyState memory currentState) {
        uint256 iy = marketExt.impliedYield();
        (, uint256 ptInLp) = marketExt.previewAssetsFromLp(bot.lpBalance);
        uint256 currentYtPtRatio = (
            ptInLp == 0 ? type(uint256).max : bot.ytBalance.divDown(ptInLp)
        );

        if (iy < specs.lowerIyLimit) {
            currentState.iyFlag = StrategyFlag.TOO_LOW;
        } else if (specs.upperIyLimit < iy && currentYtPtRatio > specs.ytPtRatioLimit) {
            currentState.iyFlag = StrategyFlag.TOO_HIGH;
        } else {
            currentState.iyFlag = StrategyFlag.GOOD;
        }

        uint256 currentSyRatio = bot.syBalance.divDown(bot.tvlInSy(marketExt));
        if (currentSyRatio > specs.floatingSyRatioLimit) {
            currentState.syRatioFlag = StrategyFlag.TOO_HIGH;
        } else {
            currentState.syRatioFlag = StrategyFlag.GOOD;
        }
    }

    function actionToTake(BotState memory botState, StrategyState memory currentState) public pure returns (ActionType) {
        if (currentState.iyFlag == StrategyFlag.TOO_LOW) {
            if (currentState.syRatioFlag == StrategyFlag.TOO_HIGH) {
                return ActionType.SwapSyToYt;
            } else {
                if (botState.lpBalance == 0) return ActionType.NONE;
                return ActionType.RemoveLiqToYt;
            }
        } else if (currentState.iyFlag == StrategyFlag.GOOD) {
            if (currentState.syRatioFlag == StrategyFlag.TOO_HIGH) {
                return ActionType.AddLiqKeepYt;
            } else {
                return ActionType.NONE;
            }
        } else {
            if (currentState.syRatioFlag == StrategyFlag.TOO_HIGH) {
                return ActionType.AddLiqFromSy;
            } else {
                if (botState.ytBalance == 0) return ActionType.NONE;
                return ActionType.AddLiqFromYt;
            }
        }
    }
}

