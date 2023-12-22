// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./MarketExtLib.sol";

struct BotState {
    uint256 lpBalance;
    uint256 ytBalance;
    uint256 syBalance;
}

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

        uint256 netYtOut = marketExt.removeLiqToYt(netLpToRemove, approxParams);

        bot.lpBalance -= netLpToRemove;
        bot.ytBalance += netYtOut;

        return true;
    }

    /// @dev Only for estimation, does not reflect exact SY amount that would be redeemed
    function tvlInSy(
        BotState memory bot,
        MarketExtState memory marketExt
    ) internal pure returns (uint256) {
        (uint256 syInLp, uint256 ptInLp) = marketExt.previewAssetsFromLp(bot.lpBalance);
        uint256 totalValue = bot.syBalance + syInLp;
        if (ptInLp <= bot.ytBalance) {
            totalValue += marketExt.previewPyToSy(ptInLp);
            totalValue += marketExt.clone().swapYtToSy(bot.ytBalance - ptInLp);
        } else {
            totalValue += marketExt.previewPyToSy(bot.ytBalance);
            totalValue += marketExt.clone().swapPtToSy(ptInLp - bot.ytBalance);
        }
        return totalValue;
    }

    function clone(BotState memory bot) internal pure returns (BotState memory) {
        return BotState(bot.lpBalance, bot.ytBalance, bot.syBalance);
    }
}

