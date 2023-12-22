// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IPMarket.sol";
import "./Math.sol";

library PendlePtOracleLib {
    using Math for uint256;
    using Math for int256;

    /**
     * This function returns the twap rate PT/Asset on market, but take into account the current rate of SY
     This is to account for special cases where underlying asset becomes insolvent and has decreasing exchangeRate
     * @param market market to get rate from
     * @param duration twap duration
     */
    function getPtToAssetRate(IPMarket market, uint32 duration) internal view returns (uint256) {
        (uint256 syIndex, uint256 pyIndex) = getSYandPYIndexCurrent(market);
        return (getPtToAssetRateRaw(market,duration) * syIndex) / pyIndex;
    }

    function getPtToAssetRateRaw(IPMarket market, uint32 duration) internal view returns (uint256) {
        uint256 expiry = market.expiry();

        if (expiry <= block.timestamp) {
            return Math.ONE;
        } else {
            uint256 lnImpliedRate = _getMarketLnImpliedRate(market, duration);
            uint256 timeToExpiry = expiry - block.timestamp;
            uint256 assetToPtRate =
                MarketMathCore._getExchangeRateFromImpliedRate(lnImpliedRate, timeToExpiry).Uint();
            return Math.ONE.divDown(assetToPtRate);
        }
    }

    function getSYandPYIndexCurrent(IPMarket market)
        internal
        view
        returns (uint256 syIndex, uint256 pyIndex)
    {
        (IStandardizedYield SY, , IPYieldToken YT) = market.readTokens();

        syIndex = SY.exchangeRate();
        uint256 pyIndexStored = YT.pyIndexStored();

        if (YT.doCacheIndexSameBlock() && YT.pyIndexLastUpdatedBlock() == block.number) {
            pyIndex = pyIndexStored;
        } else {
            pyIndex = Math.max(syIndex, pyIndexStored);
        }
    }

    function _getMarketLnImpliedRate(IPMarket market, uint32 duration)
        private
        view
        returns (uint256)
    {
        uint32[] memory durations = new uint32[](2);
        durations[0] = duration;

        uint216[] memory lnImpliedRateCumulative = market.observe(durations);
        return (lnImpliedRateCumulative[1] - lnImpliedRateCumulative[0]) / duration;
    }
}

