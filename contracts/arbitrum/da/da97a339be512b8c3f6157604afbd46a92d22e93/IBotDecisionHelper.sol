// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ITradingBotBase.sol";

enum TradeActionType {
    NONE,
    AddLiqFromYt, // Sell YT for LP
    RemoveLiqToYt // Zap out to YT,
}

enum RebalanceType {
    NONE,
    AddLiqKeepYt,
    RemoveLpAndYt,
    SellYt,
    LiquidateLp
}

interface IBotDecisionHelper {
    enum TradeActionResult {
        TARGET_NOT_REACHED,
        SUCCESS,
        FAIL_OR_TARGET_EXCEED
    }

    struct RebalanceOutput {
        RebalanceType rebalanceType;
        uint256 amountIn;
        uint256 amountOut;
        uint256 amountOut2;
    }

    struct TradeParams {
        StrategyData strategyData;
        TradeActionType action;
        uint256 targetIy;
    }

    struct TradeResult {
        TradeActionType action;
        int currentBin;
        uint256 targetIy;
        uint256 guessBotParams;
        uint256 guessIntParams;
        uint256 amountOut;
    }

    function getCurrentBin(StrategyData memory strategyData) external view returns (int256);

    function searchForBotParam(
        StrategyData memory strategyData,
        TradeActionType action,
        uint256 targetIy,
        uint256 rebalanceAdditionalCheck,
        ApproxParams memory botParams,
        ApproxParams memory intParams
    ) external view returns (uint256);

    function getRebalanceAction(address botAddress) external view returns (RebalanceOutput memory);

    function getTradeAction(address botAddress) external view returns (TradeResult memory res);

    function getBotPosition(
        address botAddress
    )
        external
        view
        returns (
            StrategyData memory strategyData,
            uint256 tvlInSy,
            uint256 iy,
            uint256 currentSyRatio,
            uint256 currentYtPtRatio
        );
}

