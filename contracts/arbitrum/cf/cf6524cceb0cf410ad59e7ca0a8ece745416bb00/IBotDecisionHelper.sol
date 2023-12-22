// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./BotSimulationLib.sol";

struct LongTradingSpecs {
    uint256 buyYtIy;
    uint256 sellYtIy;
    uint256 targetSyRatio;
    uint256 maxSyRatio;
    uint256 minYtPtRatio;
    uint256 numOfBins;
}

enum ActionType {
    NONE,
    AddLiqFromYt, // Sell YT for LP
    RemoveLiqToYt // Zap out to YT,
}

struct StrategyData {
    BotState botState;
    MarketExtState marketExt;
    LongTradingSpecs specs;
}

interface IBotDecisionHelper {
    enum RebalanceResult {
        TARGET_NOT_REACHED,
        SUCCESS,
        FAIL_OR_TARGET_EXCEED
    }

    struct RebalanceDetails {
        StrategyData strategyData;
        ActionType action;
        uint256 targetIy;
    }

    struct ActionToTakeResult {
        ActionType action;
        int currentBin;
        uint256 targetIy;
        uint256 guessBotParams;
        uint256 guessIntParams;
        uint256 amountOut;
    }

    function getCurrentBin(StrategyData memory strategyData) external view returns (int256);

    function previewAction(
        StrategyData memory strategyData,
        ActionType action,
        uint256 botParam,
        ApproxParams memory swapApproxParams
    ) external view returns (bool, BotState memory, MarketExtState memory);

    function botExtStats(
        StrategyData memory strategyData
    )
        external
        view
        returns (uint256 tvlInSy, uint256 iy, uint256 currentSyRatio, uint256 currentYtPtRatio);

    function searchForBotParam(
        StrategyData memory strategyData,
        ActionType action,
        uint256 targetIy,
        uint256 rebalanceAdditionalCheck,
        ApproxParams memory botParams,
        ApproxParams memory intParams
    ) external view returns (uint256);

    function getAvailableZpiAmount(address botAddress) external returns (uint256 amountSyToZpi);
}

