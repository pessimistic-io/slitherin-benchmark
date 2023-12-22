// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./BotSimulationLib.sol";

struct LongTradingSpecs {
    uint256 lowerIyLimit; // apeYtApy
    uint256 upperIyLimit; // sellYtApy
    uint256 floatingSyRatioLimit; // h_r
    uint256 floatingSyRatioTarget; // l_r
    uint256 ytPtRatioLimit; // h_x
    uint256 ytPtRatioTarget; // l_x
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

interface IBotDecisionHelper {
    enum RebalanceResult {
        FAIL,
        TARGET_REACHED,
        TARGET_NOT_REACHED
    }

    struct RebalanceDetails {
        BotState bot;
        MarketExtState marketExt;
        LongTradingSpecs specs;
        ActionType action;
    }

    function searchForBotParam(
        BotState memory bot,
        MarketExtState memory marketExt,
        LongTradingSpecs memory specs,
        ActionType action,
        ApproxParams memory botParams,
        ApproxParams memory intParams
    ) external pure returns (uint256, RebalanceResult);

    function searchForIntParam(
        MarketExtState memory marketExt,
        ActionType action,
        uint256 botParam,
        ApproxParams memory intParams
    ) external pure returns (uint256);

    function strategyState(
        BotState memory bot,
        MarketExtState memory marketExt,
        LongTradingSpecs memory specs
    ) external pure returns (StrategyState memory);

    function actionToTake(
        BotState memory botState,
        StrategyState memory currentState
    ) external pure returns (ActionType);

    function previewAction(
        BotState memory botData,
        MarketExtState memory marketExtData,
        ActionType action,
        uint256 botParam,
        ApproxParams memory swapApproxParams
    ) external pure returns (bool, BotState memory, MarketExtState memory);

    function botExtStats(
        BotState memory bot,
        MarketExtState memory marketExt
    )
        external
        pure
        returns (uint256 tvlInSy, uint256 iy, uint256 currentSyRatio, uint256 currentYtPtRatio);
}

