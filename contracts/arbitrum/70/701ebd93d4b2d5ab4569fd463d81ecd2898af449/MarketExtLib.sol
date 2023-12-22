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
    using MarketApproxPtOutLib for MarketState;
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

        netLpOut = addLiqDual(marketExt, netSyIn - netSyToPt, netYtOut);
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

        netLpOut = addLiqDual(marketExt, netSyToAdd, netPtFromSwap);
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

        netLpOut = addLiqDual(marketExt, netSyToAdd, netPtToAdd);
    }

    /// @dev Simulates PendleRouter's removeLiquidityDualSyAndPt then swapExactPtForYt
    function removeLiqToYt(
        MarketExtState memory marketExt,
        uint256 netLpToRemove,
        ApproxParams memory approxParams
    ) internal pure returns (uint256 netYtOut, uint256 totalPtToSwap) {
        (uint256 netSyRemoved, uint256 netPtRemoved) = removeLiqDual(marketExt, netLpToRemove);

        uint256 netYtFromSy = marketExt.index.syToAsset(netSyRemoved);
        uint256 netPtToSwap = netPtRemoved + netYtFromSy;

        uint256 netYtFromSwap;
        (netYtFromSwap, totalPtToSwap, ) = marketExt.state.approxSwapExactPtForYt(
            marketExt.index,
            netPtToSwap,
            marketExt.blockTime,
            clone(approxParams)
        );

        marketExt.state.swapExactPtForSy(marketExt.index, totalPtToSwap, marketExt.blockTime);

        netYtOut = netYtFromSy + netYtFromSwap;
    }

    /// @dev Simplified version of MarketMathCore's addLiquidity
    function addLiqDual(
        MarketExtState memory marketExt,
        uint256 netSyIn,
        uint256 netPtIn
    ) internal pure returns (uint256 /*netLpOut*/) {
        require(
            !MiniHelpers.isExpired(marketExt.state.expiry, marketExt.blockTime),
            "MarketExtLib: expired market"
        );
        require(marketExt.state.totalLp > 0, "MarketExtLib: LP < 0");

        int256 syDesired = netSyIn.Int();
        int256 ptDesired = netPtIn.Int();
        int256 lpToAccount;
        int256 ptUsed;
        int256 syUsed;

        int256 netLpByPt = (ptDesired * marketExt.state.totalLp) / marketExt.state.totalPt;
        int256 netLpBySy = (syDesired * marketExt.state.totalLp) / marketExt.state.totalSy;
        if (netLpByPt < netLpBySy) {
            lpToAccount = netLpByPt;
            ptUsed = ptDesired;
            syUsed = (marketExt.state.totalSy * lpToAccount) / marketExt.state.totalLp;
        } else {
            lpToAccount = netLpBySy;
            syUsed = syDesired;
            ptUsed = (marketExt.state.totalPt * lpToAccount) / marketExt.state.totalLp;
        }

        marketExt.state.totalSy += syUsed;
        marketExt.state.totalPt += ptUsed;
        marketExt.state.totalLp += lpToAccount;

        return lpToAccount.Uint();
    }

    /// @dev Simplified version of MarketMathCore's removeLiquidity
    function removeLiqDual(
        MarketExtState memory marketExt,
        uint256 netLpToRemove
    ) internal pure returns (uint256 /*netSyToAccount*/, uint256 /*netPtToAccount*/) {
        int256 lpToRemove = netLpToRemove.Int();

        int256 netSyToAccount = (lpToRemove * marketExt.state.totalSy) / marketExt.state.totalLp;
        int256 netPtToAccount = (lpToRemove * marketExt.state.totalPt) / marketExt.state.totalLp;

        marketExt.state.totalLp = marketExt.state.totalLp.subNoNeg(lpToRemove);
        marketExt.state.totalPt = marketExt.state.totalPt.subNoNeg(netPtToAccount);
        marketExt.state.totalSy = marketExt.state.totalSy.subNoNeg(netSyToAccount);

        return (netSyToAccount.Uint(), netPtToAccount.Uint());
    }

    function swapPtToYt(
        MarketExtState memory marketExt,
        uint256 exactPtIn,
        ApproxParams memory approxParams
    ) internal pure returns (uint256 netYtOut, uint256 totalPtToSwap) {
        (netYtOut, totalPtToSwap,) = marketExt.state.approxSwapExactPtForYt(
            marketExt.index,
            exactPtIn,
            marketExt.blockTime,
            approxParams
        );

        marketExt.state.swapExactPtForSy(marketExt.index, totalPtToSwap, marketExt.blockTime);
    }

    function swapYtToPt(
        MarketExtState memory marketExt,
        uint256 exactYtIn,
        ApproxParams memory approxParams
    ) internal pure returns (uint256 netPtOut, uint256 totalPtSwapped) {
        (netPtOut, totalPtSwapped,) = marketExt.state.approxSwapExactYtForPt(
            marketExt.index,
            exactYtIn,
            marketExt.blockTime,
            approxParams
        );

        marketExt.state.swapSyForExactPt(marketExt.index, totalPtSwapped, marketExt.blockTime);
    }

    function previewPyToSy(
        MarketExtState memory marketExt,
        uint256 netPYToRedeem
    ) internal pure returns (uint256) {
        return marketExt.index.assetToSy(netPYToRedeem);
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
            (MarketApproxPtInLib.calcMaxPtIn(
                marketExt.state,
                marketExt.state.getMarketPreCompute(marketExt.index, marketExt.blockTime)
            ) * 9) / 10;
    }

    function calcMaxPtOut(MarketExtState memory marketExt) internal pure returns (uint256) {
        return
            MarketApproxPtOutLib.calcMaxPtOut(
                marketExt.state.getMarketPreCompute(marketExt.index, marketExt.blockTime),
                marketExt.state.totalPt
            );
    }
}

