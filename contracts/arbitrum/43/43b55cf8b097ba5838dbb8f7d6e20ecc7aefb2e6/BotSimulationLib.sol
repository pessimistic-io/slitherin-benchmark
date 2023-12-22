// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./MarketExtLib.sol";
import "./IBotDecisionHelper.sol";

library BotSimulationLib {
    using MarketMathCore for MarketState;
    using MarketExtLib for MarketExtState;
    using Math for uint256;
    using Math for int256;

    function swapSyToYt(
        BotState memory bot,
        MarketExtState memory marketExt,
        uint256 exactYtOut
    ) internal pure returns (bool /*success*/) {
        uint256 netSyIn = marketExt.swapSyToYt(exactYtOut);

        if (netSyIn > bot.syBalance) return false;

        bot.syBalance -= netSyIn;
        bot.ytBalance += exactYtOut;

        return true;
    }

    function addLiqKeepYt(
        BotState memory bot,
        MarketExtState memory marketExt,
        uint256 netSyIn
    ) internal pure returns (bool /*success*/) {
        if (netSyIn > bot.syBalance) return false;

        (uint256 netLpOut, uint256 netYtOut) = marketExt.addLiqKeepYt(netSyIn);

        bot.syBalance -= netSyIn;
        bot.lpBalance += netLpOut;
        bot.ytBalance += netYtOut;

        return true;
    }

    function addLiqFromSy(
        BotState memory bot,
        MarketExtState memory marketExt,
        uint256 netPtFromSwap
    ) internal pure returns (bool /*success*/) {
        (uint256 netLpOut, uint256 netSyIn) = marketExt.addLiqFromSy(netPtFromSwap);

        if (netSyIn > bot.syBalance) return false;

        bot.syBalance -= netSyIn;
        bot.lpBalance += netLpOut;

        return true;
    }

    function addLiqFromYt(
        BotState memory bot,
        MarketExtState memory marketExt,
        uint256 netPtFromSwap
    ) internal pure returns (bool /*success*/) {
        (uint256 netLpOut, uint256 netYtIn) = marketExt.addLiqFromYt(netPtFromSwap);

        if (netYtIn > bot.ytBalance) return false;

        bot.ytBalance -= netYtIn;
        bot.lpBalance += netLpOut;

        return true;
    }

    function removeLiqToYt(
        BotState memory bot,
        MarketExtState memory marketExt,
        uint256 netLpToRemove,
        ApproxParams memory approxParams
    ) internal pure returns (bool /*success*/) {
        if (netLpToRemove > bot.lpBalance) return false;

        (uint256 netYtOut, ) = marketExt.removeLiqToYt(
            netLpToRemove,
            cloneApproxParams(approxParams)
        );

        bot.lpBalance -= netLpToRemove;
        bot.ytBalance += netYtOut;

        return true;
    }

    function swapPtToYt(
        BotState memory bot,
        MarketExtState memory marketExt,
        uint256 netPtToSwap,
        ApproxParams memory approxParams
    ) internal pure returns (bool /*success*/) {
        if (netPtToSwap > bot.ptBalance) return false;
        (uint256 netYtOut, ) = marketExt.swapPtToYt(netPtToSwap, cloneApproxParams(approxParams));
        bot.ptBalance -= netPtToSwap;
        bot.ytBalance += netYtOut;
        return true;
    }

    function swapYtToPt(
        BotState memory bot,
        MarketExtState memory marketExt,
        uint256 netYtToSwap,
        ApproxParams memory approxParams
    ) internal pure returns (bool /*success*/) {
        if (netYtToSwap > bot.ytBalance) return false;
        (uint256 netPtOut, ) = marketExt.swapYtToPt(netYtToSwap, cloneApproxParams(approxParams));
        bot.ptBalance += netPtOut;
        bot.ytBalance -= netYtToSwap;
        return true;
    }

    function tvlInSy(
        BotState memory bot,
        MarketExtState memory marketExt
    ) internal pure returns (uint256) {
        MarketExtState memory marketExtClone = marketExt.clone();

        (uint256 syInLp, uint256 ptInLp) = marketExtClone.removeLiqDual(bot.lpBalance);
        uint256 totalValue = bot.syBalance + syInLp;

        uint256 totalPt = ptInLp + bot.ptBalance;
        if (totalPt <= bot.ytBalance) {
            totalValue += marketExtClone.previewPyToSy(totalPt);
            totalValue += marketExtClone.swapYtToSy(bot.ytBalance - totalPt);
        } else {
            totalValue += marketExtClone.previewPyToSy(bot.ytBalance);
            totalValue += marketExtClone.swapPtToSy(totalPt - bot.ytBalance);
        }
        return totalValue;
    }

    function clone(BotState memory bot) internal pure returns (BotState memory) {
        return BotState(bot.lpBalance, bot.ytBalance, bot.ptBalance, bot.syBalance, bot.buyBins);
    }

    function cloneApproxParams(
        ApproxParams memory params
    ) internal pure returns (ApproxParams memory) {
        return
            ApproxParams(
                params.guessMin,
                params.guessMax,
                params.guessOffchain,
                params.maxIteration,
                params.eps
            );
    }
}

