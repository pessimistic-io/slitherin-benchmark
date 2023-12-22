// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ITradingBotBase.sol";
import "./IBotDecisionHelper.sol";

interface ILongYieldTradingBot is ITradingBotBase {
    event SwapSyToYt(ApproxParams botParams, uint256 maxSyIn, uint256 exactYtOut, uint256 netSyIn);

    event AddLiqKeepYt(
        uint256 netSyIn,
        uint256 netLpOut,
        uint256 netYtOut
    );

    event AddLiqFromSy(ApproxParams botParams, uint256 maxSyIn, uint256 netSyIn, uint256 netLpOut);

    event AddLiqFromYt(ApproxParams botParams, uint256 netYtIn, uint256 netLpOut);

    event RemoveLiqToYt(ApproxParams botParams, uint256 netLpIn, uint256 netYtOut);

    struct AddLiqFromYtInput {
        ApproxParams botParams;
        uint256 minLpOut;
        uint256 targetIy;
        int256 currentBin;
    }

    struct RemoveLiqToYtInput {
        ApproxParams botParams;
        ApproxParams guessTotalPtToSwap;
        uint256 minYtOut;
        uint256 targetIy;
        int256 currentBin;
    }


    function addLiqKeepYt(
        uint256 netSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external returns (uint256 netLpOut, uint256 netYtOut);

    function addLiqFromYt(
        AddLiqFromYtInput calldata inputParams
    ) external returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netYtIn);

    function removeLiqToYt(
        RemoveLiqToYtInput calldata inputParams
    ) external returns (uint256 netLpRemoved, uint256 netYtOut);
}

