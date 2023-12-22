// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ITradingBotBase.sol";
import "./BotDecisionLib.sol";

interface ILongYieldTradingBot {
    function setSpecs(LongTradingSpecs calldata _specs) external;

    event SwapSyToYt(
        StrategyState state,
        ApproxParams botParams,
        uint256 maxSyIn,
        uint256 exactYtOut,
        uint256 netSyIn
    );

    event AddLiqKeepYt(
        StrategyState state,
        ApproxParams botParams,
        uint256 maxSyIn,
        uint256 netSyIn,
        uint256 netLpOut,
        uint256 netYtOut
    );

    event AddLiqFromSy(
        StrategyState state,
        ApproxParams botParams,
        uint256 maxSyIn,
        uint256 netSyIn,
        uint256 netLpOut
    );

    event AddLiqFromYt(
        StrategyState state,
        ApproxParams botParams,
        uint256 maxYtIn,
        uint256 netYtIn,
        uint256 netLpOut
    );

    event RemoveLiqToYt(
        StrategyState state,
        ApproxParams botParams,
        uint256 maxLpRemoved,
        uint256 netLpIn,
        uint256 netYtOut
    );

    function swapSyToYt(
        address router,
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        uint256 minYtOut,
        uint256 maxSyIn
    ) external returns (uint256 exactYtOut, uint256 netSyIn);

    function addLiqKeepYt(
        address router,
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        uint256 maxSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external returns (uint256 netSyIn, uint256 netLpOut, uint256 netYtOut);

    function addLiqFromSy(
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        uint256 minLpOut,
        uint256 maxSyIn
    ) external returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netSyIn);

    function addLiqFromYt(
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        uint256 minLpOut,
        uint256 maxYtIn
    ) external returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netYtIn);

    function removeLiqToYt(
        StrategyState memory oldState,
        ApproxParams calldata botParams,
        ApproxParams calldata guessTotalPtToSwap,
        uint256 maxLpRemoved,
        uint256 minYtOut
    ) external returns (uint256 netLpRemoved, uint256 netYtOut, uint256 totalPtToSwap);
}

