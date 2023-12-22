// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ITradingBotBase.sol";
import "./IBotDecisionHelper.sol";

interface ILongYieldTradingBot is ITradingBotBase {
    event AddLiqKeepYt(uint256 netSyIn, uint256 netLpOut, uint256 netYtOut);

    event AddLiqFromYt(ApproxParams botParams, uint256 netYtIn, uint256 netLpOut);

    event RemoveLiqToYt(ApproxParams botParams, uint256 netLpIn, uint256 netYtOut);

    // Naming convention: *botParams* is the guessed amount of token used to perform the action
    // For example, if we want to add liquidity from yt, we need to guess the amount of YT to be used
    // In case the action requires an approximation on swapping, the approx params is denoted as *guessTotalPtToSwap*

    struct AddLiqFromYtInput {
        ApproxParams botParams; // bot params to perform the action
        uint256 minLpOut; // minimum lp out acceptable
        uint256 targetIy; // target implied yield (middle of some bin)
        int256 currentBin; // current bin we were sitting on (ensuring that the action is still valid)
    }

    struct RemoveLiqToYtInput {
        ApproxParams botParams; // bot params to perform the action
        ApproxParams guessTotalPtToSwap; // swap SY to YT approximation
        uint256 minYtOut; // minimum yt out acceptable
        uint256 targetIy; // target implied yield (middle of some bin)
        int256 currentBin; // current bin we were sitting on (ensuring that the action is still valid)
    }

    /**
     * To perfrom a zero price impact zap (add liquidity keep yt)
     * @param netSyIn total sy to zap
     * @param minLpOut minimum lp out acceptable
     * @param minYtOut minimum yt out acceptable
     * @return netLpOut
     * @return netYtOut
     */
    function addLiqKeepYt(
        uint256 netSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external returns (uint256 netLpOut, uint256 netYtOut);

    /**
     * To perform a zap by swapping YT to SY/PT
     * @param inputParams Input params for adding liquidity from YT (see struct for details)
     * @return netPtFromSwap
     * @return netLpOut
     * @return netYtIn
     */
    function addLiqFromYt(
        AddLiqFromYtInput calldata inputParams
    ) external returns (uint256 netPtFromSwap, uint256 netLpOut, uint256 netYtIn);

    /**
     * To perform a zap out by swapping SY/PT (removed from LP) to YT
     * @param inputParams Input params for removing liquidity to YT (see struct for details)
     * @return netLpRemoved
     * @return netYtOut
     */
    function removeLiqToYt(
        RemoveLiqToYtInput calldata inputParams
    ) external returns (uint256 netLpRemoved, uint256 netYtOut);

    function swapYtToSy(uint256 netYtToSell, uint256 minSyOut) external returns (uint256 netSyOut);

    function removeLiquidityToSy(
        uint256 netLpToRemove,
        uint256 minSyOut
    ) external returns (uint256 netSyOut);
}

