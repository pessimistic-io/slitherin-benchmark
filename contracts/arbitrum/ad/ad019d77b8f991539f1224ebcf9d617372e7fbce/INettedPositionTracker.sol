// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

interface INettedPositionTracker {
    struct NettedPrices {
        uint256 stable;
        uint256 eth;
        uint256 btc;
        uint256 link;
        uint256 uni;
    }

    function settleNettingPositionPnl(
        int256[5][5] memory internalPositions,
        NettedPrices memory assetPrices,
        NettedPrices memory lastAssetPrices,
        uint256[5] memory vaultGlpAmount,
        uint256 glpPrice,
        uint256 pnlSumThreshold
    )
        external
        view
        returns (
            uint256[5] memory settledVaultGlpAmount,
            int256[5] memory nettedPnl,
            int256[5] memory glpPnl,
            int256[5] memory percentPriceChange
        );
}

