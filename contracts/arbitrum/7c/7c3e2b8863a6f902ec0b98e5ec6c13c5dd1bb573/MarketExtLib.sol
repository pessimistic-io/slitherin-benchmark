// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IPMarket.sol";
import "./PYIndex.sol";
import "./MarketApproxLib.sol";

struct MarketExtState {
    MarketState state;
    PYIndex index;
    uint256 blockTime;
}

library MarketExtLib {
    using MarketMathCore for MarketState;
    using MarketApproxPtInLib for MarketState;
    using PYIndexLib for PYIndex;
    using PYIndexLib for IPYieldToken;
    using LogExpMath for uint256;
    using Math for uint256;
    using Math for int256;

    uint256 public constant ONE_YEAR = 31536000;

    /// @dev Simulates PendleRouter's swapExactYtForSy
    function swapYtToSy(
        MarketExtState memory marketExt,
        uint256 exactYtIn
    ) internal pure returns (uint256 /*netSyOut*/) {
        (uint256 netSyOwedInt, , ) = marketExt.state.swapSyForExactPt(
            marketExt.index,
            exactYtIn,
            marketExt.blockTime
        );

        uint256 netPYToRepaySyOwedInt = marketExt.index.syToAssetUp(netSyOwedInt);
        uint256 netPYToRedeemSyOutInt = exactYtIn - netPYToRepaySyOwedInt;

        return marketExt.index.assetToSy(netPYToRedeemSyOutInt);
    }

    /// @dev Simulates PendleRouter's swapSyForExactYt
    function swapSyToYt(
        MarketExtState memory marketExt,
        uint256 exactYtOut
    ) internal pure returns (uint256 /*netSyIn*/) {
        (uint256 netSyReceivedInt, , ) = marketExt.state.swapExactPtForSy(
            marketExt.index,
            exactYtOut,
            marketExt.blockTime
        );

        uint256 totalSyNeedInt = marketExt.index.assetToSyUp(exactYtOut);
        return totalSyNeedInt.subMax0(netSyReceivedInt);
    }

    /// @dev Simulates PendleRouter's swapExactPtForSy
    function swapPtToSy(
        MarketExtState memory marketExt,
        uint256 exactPtIn
    ) internal pure returns (uint256 netSyOut) {
        (netSyOut, , ) = marketExt.state.swapExactPtForSy(
            marketExt.index,
            exactPtIn,
            marketExt.blockTime
        );
    }

    /// @dev Simulates PendleRouter's addLiquiditySingleSyKeepYt
    function addLiqKeepYt(
        MarketExtState memory marketExt,
        uint256 netSyIn
    ) internal pure returns (uint256 netLpOut, uint256 netYtOut) {
        uint256 netSyToPt = (netSyIn * marketExt.state.totalPt.Uint()) /
            (marketExt.state.totalPt.Uint() +
                marketExt.index.syToAsset(marketExt.state.totalSy.Uint()));

        netYtOut = marketExt.index.syToAsset(netSyToPt);

        (, netLpOut, , ) = marketExt.state.addLiquidity(
            netSyIn - netSyToPt,
            netYtOut,
            marketExt.blockTime
        );
    }

    function addLiqFromSy(
        MarketExtState memory marketExt,
        uint256 netPtFromSwap
    ) internal pure returns (uint256 netLpOut, uint256 netSyIn) {
        (uint256 netSyToSwap, , ) = marketExt.state.swapSyForExactPt(
            marketExt.index,
            netPtFromSwap,
            marketExt.blockTime
        );
        uint256 netSyToAdd = (netPtFromSwap * marketExt.state.totalSy.Uint()) /
            marketExt.state.totalPt.Uint();

        (, netLpOut, , ) = marketExt.state.addLiquidity(
            netSyToAdd,
            netPtFromSwap,
            marketExt.blockTime
        );
        netSyIn = netSyToSwap + netSyToAdd;
    }

    function addLiqFromYt(
        MarketExtState memory marketExt,
        uint256 netPtFromSwap
    ) internal pure returns (uint256 netLpOut, uint256 netYtIn) {
        (uint256 netSyToSwap, , ) = marketExt.state.swapSyForExactPt(
            marketExt.index,
            netPtFromSwap,
            marketExt.blockTime
        );

        uint256 pyIndex = PYIndex.unwrap(marketExt.index);
        uint256 netPtToAddNumerator = (netPtFromSwap * Math.ONE - netSyToSwap * pyIndex);
        uint256 netPtToAddDenominator = (Math.ONE +
            (marketExt.state.totalSy.Uint() * pyIndex) /
            marketExt.state.totalPt.Uint());
        uint256 netPtToAdd = netPtToAddNumerator / netPtToAddDenominator;

        netYtIn = netPtFromSwap - netPtToAdd;

        uint256 netSyFromPy = marketExt.index.assetToSy(netYtIn);
        uint256 netSyToAdd = netSyFromPy - netSyToSwap;

        (, netLpOut, , ) = marketExt.state.addLiquidity(
            netSyToAdd,
            netPtToAdd,
            marketExt.blockTime
        );
    }

    /// @dev Simulates PendleRouter's removeLiquidityDualSyAndPt then swapExactPtForYt
    function removeLiqToYt(
        MarketExtState memory marketExt,
        uint256 netLpToRemove,
        ApproxParams memory approxParams
    ) internal pure returns (uint256 /*netYtOut*/) {
        (uint256 netSyRemoved, uint256 netPtRemoved) = marketExt.state.removeLiquidity(
            netLpToRemove
        );

        uint256 netYtFromSy = marketExt.index.syToAsset(netSyRemoved);
        uint256 netPtToSwap = netPtRemoved + netYtFromSy;

        (uint256 netYtFromSwap, uint256 totalPtToSwap, ) = marketExt.state.approxSwapExactPtForYt(
            marketExt.index,
            netPtToSwap,
            marketExt.blockTime,
            clone(approxParams)
        );

        marketExt.state.swapExactPtForSy(marketExt.index, totalPtToSwap, marketExt.blockTime);

        return netYtFromSy + netYtFromSwap;
    }

    function previewPyToSy(
        MarketExtState memory marketExt,
        uint256 netPYToRedeem
    ) internal pure returns (uint256) {
        return marketExt.index.assetToSy(netPYToRedeem);
    }

    function previewAssetsFromLp(
        MarketExtState memory marketExt,
        uint256 lpBalance
    ) internal pure returns (uint256 syInLp, uint256 ptInLp) {
        syInLp = (lpBalance * marketExt.state.totalSy.Uint()) / marketExt.state.totalLp.Uint();
        ptInLp = (lpBalance * marketExt.state.totalPt.Uint()) / marketExt.state.totalLp.Uint();
    }

    /// @notice Returns the trade exchange rate, fee excluded
    function exchangeRate(MarketExtState memory marketExt) internal pure returns (uint256) {
        MarketPreCompute memory comp = marketExt.state.getMarketPreCompute(
            marketExt.index,
            marketExt.blockTime
        );

        int256 preFeeExchangeRate = MarketMathCore._getExchangeRate(
            marketExt.state.totalPt,
            comp.totalAsset,
            comp.rateScalar,
            comp.rateAnchor,
            0
        );

        return preFeeExchangeRate.Uint();
    }

    function impliedYield(MarketExtState memory marketExt) internal pure returns (uint256) {
        return
            exchangeRate(marketExt).pow(
                ONE_YEAR.divDown(marketExt.state.expiry - marketExt.blockTime)
            ) - Math.ONE;
    }

    function clone(MarketState memory state) internal pure returns (MarketState memory) {
        return
            MarketState(
                state.totalPt,
                state.totalSy,
                state.totalLp,
                state.treasury,
                state.scalarRoot,
                state.expiry,
                state.lnFeeRateRoot,
                state.reserveFeePercent,
                state.lastLnImpliedRate
            );
    }

    function clone(MarketExtState memory marketExt) internal pure returns (MarketExtState memory) {
        return MarketExtState(clone(marketExt.state), marketExt.index, marketExt.blockTime);
    }

    function clone(ApproxParams memory params) internal pure returns (ApproxParams memory) {
        return
            ApproxParams(
                params.guessMin,
                params.guessMax,
                params.guessOffchain,
                params.maxIteration,
                params.eps
            );
    }

    function calcMaxPtIn(MarketExtState memory marketExt) internal pure returns (uint256) {
        return
            MarketApproxPtInLib.calcMaxPtIn(
                marketExt.state,
                marketExt.state.getMarketPreCompute(marketExt.index, marketExt.blockTime)
            ) * 9 / 10;
    }

    function calcMaxPtOut(MarketExtState memory marketExt) internal pure returns (uint256) {
        return
            MarketApproxPtOutLib.calcMaxPtOut(
                marketExt.state.getMarketPreCompute(marketExt.index, marketExt.blockTime),
                marketExt.state.totalPt
            );
    }
}

