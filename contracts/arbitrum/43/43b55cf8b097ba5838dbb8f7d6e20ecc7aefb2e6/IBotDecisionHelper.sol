// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ITradingBotBase.sol";

enum ActionType {
    NONE,
    AddLiqFromYt, // Sell YT for LP
    RemoveLiqToYt, // Zap out to YT,
    SwapPtForYt,
    SwapYtForPt
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

    function getFloatingSyAmount(address botAddress) external returns (uint256 floatingSyAmount);

    function getActionDetails(address botAddress) external returns (ActionToTakeResult memory res);
}

