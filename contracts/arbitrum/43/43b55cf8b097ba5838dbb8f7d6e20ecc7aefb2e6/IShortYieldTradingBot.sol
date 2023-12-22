// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./ITradingBotBase.sol";
import "./IBotDecisionHelper.sol";

interface IShortYieldTradingBot is ITradingBotBase {
    event MintPy(uint256 netSyIn, uint256 netPyOut);

    event SwapPtForYt(SwapInput inputParams, uint256 netYtOut);

    event SwapYtForPt(SwapInput inputParams, uint256 netPtOut);

    struct SwapInput {
        ApproxParams botParams;
        ApproxParams guessTotalPtToSwap;
        uint256 minAmountOut;
        uint256 targetIy;
        int256 currentBin;
    }

    function mintPY(uint256 netSyIn, uint256 minPyOut) external returns (uint256 netPyOut);

    function swapPtForYt(SwapInput calldata inputParams) external returns (uint256 netYtOut);

    function swapYtForPt(SwapInput calldata inputParams) external returns (uint256 netPtOut);
}

