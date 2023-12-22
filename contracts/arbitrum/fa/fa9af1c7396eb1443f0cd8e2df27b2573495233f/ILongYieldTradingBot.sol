// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ITradingBotBase.sol";
import "./IBotDecisionHelper.sol";

interface ILongYieldTradingBot is ITradingBotBase {
    event SwapSyToYt(ApproxParams botParams, uint256 maxSyIn, uint256 exactYtOut, uint256 netSyIn);

    event AddLiqKeepYt(
        ApproxParams botParams,
        uint256 maxSyIn,
        uint256 netSyIn,
        uint256 netLpOut,
        uint256 netYtOut
    );

    event AddLiqFromSy(ApproxParams botParams, uint256 maxSyIn, uint256 netSyIn, uint256 netLpOut);

    event AddLiqFromYt(ApproxParams botParams, uint256 maxYtIn, uint256 netYtIn, uint256 netLpOut);

    event RemoveLiqToYt(
        ApproxParams botParams,
        uint256 maxLpRemoved,
        uint256 netLpIn,
        uint256 netYtOut
    );

    function setSpecs(LongTradingSpecs calldata _specs) external;

    function swapSyToYt(
        address router,
        ApproxParams calldata botParams,
        uint256 minYtOut,
        uint256 maxSyIn
    ) external returns (uint256 exactYtOut, uint256 netSyIn);

    function addLiqKeepYt(
        address router,
        ApproxParams calldata botParams,
        uint256 maxSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external returns (uint256 netSyIn, uint256 netLpOut, uint256 netYtOut);

    function addLiqFromSy(
        ApproxParams calldata botParams,
        uint256 minLpOut,
        uint256 maxSyIn
    ) external returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netSyIn);

    function addLiqFromYt(
        ApproxParams calldata botParams,
        uint256 minLpOut,
        uint256 maxYtIn
    ) external returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netYtIn);

    function removeLiqToYt(
        ApproxParams calldata botParams,
        ApproxParams calldata guessTotalPtToSwap,
        uint256 maxLpRemoved,
        uint256 minYtOut
    ) external returns (uint256 netLpRemoved, uint256 netYtOut, uint256 totalPtToSwap);
}

