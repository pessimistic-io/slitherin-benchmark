// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./MarketExtLib.sol";
import "./IBotDecisionHelper.sol";
import "./PendleLpOracleLib.sol";

library TvlLib {
    using MarketMathCore for MarketState;
    using MarketExtLib for MarketExtState;
    using Math for uint256;
    using Math for int256;
    using PendleLpOracleLib for IPMarket;
    using PendlePtOracleLib for IPMarket;
    using PYIndexLib for PYIndex;

    uint32 internal constant ORACLE_DURATION = 1800;

    /**
     * @param market market address
     * @param bot currnet bot state
     * @return tvl total value locked in SY (excluding uncompounded reward tokens/interest) by oracle prices
     */
    function getOracleTvl(address market, BotState memory bot) public view returns (uint256) {
        PYIndex index = IPMarket(market)._getPYIndexCurrent();

        uint256 tvlInAsset;
        if (bot.lpBalance > 0) {
            tvlInAsset += bot.lpBalance.mulDown(
                IPMarket(market).getLpToAssetRate(ORACLE_DURATION)
            );
        }

        if (bot.ptBalance + bot.ytBalance > 0) {
            uint256 ptPrice = IPMarket(market).getPtToAssetRate(ORACLE_DURATION);
            uint256 ytPrice = Math.ONE - ptPrice;
            tvlInAsset += bot.ptBalance.mulDown(ptPrice) + bot.ytBalance.mulDown(ytPrice);
        }

        return index.assetToSy(tvlInAsset) + bot.syBalance;
    }

    /**
     * 
     * @param bot current bot state
     * @param marketExt current market state
     * @return Total value locked in SY (excluding uncompounded reward tokens/interest) if we perform liquidation
     * on all bot's assets
     */
    function getLiquidateTvl(
        BotState memory bot,
        MarketExtState memory marketExt
    ) public pure returns (uint256) {
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
}

