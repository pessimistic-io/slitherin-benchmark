// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./TradingBotBase.sol";
import "./BotActionCallback.sol";

abstract contract BotActionHelper is TradingBotBase, BotActionCallback {
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;
    using MarketMathCore for MarketState;
    using MarketApproxPtInLib for MarketState;
    using Math for int256;

    bytes internal constant EMPTY_BYTES = abi.encode();

    function _swapSyToYt(
        address router,
        uint256 exactYtOut,
        uint256 maxSyIn
    ) internal returns (uint256 netSyIn) {
        (netSyIn, ) = IPAllAction(router).swapSyForExactYt(
            address(this),
            market,
            exactYtOut,
            maxSyIn
        );
    }

    function _addLiqKeepYt(
        address router,
        uint256 netSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) internal returns (uint256 /*netLpOut*/, uint256 /*netYtOut*/) {
        return
            IPAllAction(router).addLiquiditySingleSyKeepYt(
                address(this),
                market,
                netSyIn,
                minLpOut,
                minYtOut
            );
    }

    /// @dev Mimics PendleRouter's addLiquiditySingleSy
    function _addLiqFromSy(
        uint256 netPtFromSwap,
        uint256 minLpOut,
        uint256 maxSyIn
    ) internal returns (uint256 netLpOut, uint256 netSyIn) {
        MarketState memory state = IPMarket(market).readState(address(this));
        PYIndex index = IPYieldToken(YT).newIndex();

        (uint256 netSyToSwap, , ) = state.swapSyForExactPt(index, netPtFromSwap, block.timestamp);
        (, , uint256 netSyToAdd, ) = state.addLiquidity(
            maxSyIn - netSyToSwap,
            netPtFromSwap,
            block.timestamp
        ); // ensures netSyToAdd <= maxSyIn - netSyToSwap
        netSyIn = netSyToSwap + netSyToAdd;

        _transferOut(SY, market, netSyIn);
        IPMarket(market).swapSyForExactPt(market, netPtFromSwap, EMPTY_BYTES); // PT goes to market for LP
        (netLpOut, , ) = IPMarket(market).mint(address(this), netSyToAdd, netPtFromSwap);

        if (netLpOut < minLpOut) revert Errors.BotInsufficientLpOut(netLpOut, minLpOut);
    }

    function _addLiqFromYt(
        uint256 netPtFromSwap,
        uint256 minLpOut
    ) internal returns (uint256 netLpOut, uint256 netYtIn) {
        MarketState memory state = IPMarket(market).readState(address(this));
        PYIndex index = IPYieldToken(YT).newIndex();

        (uint256 netSyToSwap, , ) = state.swapSyForExactPt(index, netPtFromSwap, block.timestamp);

        // (1) --> netPtRedeemSy = netPtFromSwap - netPtToAdd
        // (2) --> (netPtRedeemSy * ONE / pyIndex) = (netPtToAdd * totalSy / totalPt) + netSyToSwap
        // (2) * pyIndex / ONE --> netPtRedeemSy = (netPtToAdd * totalSy / totalPt * pyIndex / ONE) + netSyToSwap * pyIndex / ONE
        // ==> netPtFromSwap - netPtToAdd = (netPtToAdd * totalSy / totalPt * pyIndex / ONE) + netSyToSwap * pyIndex / ONE
        // ==> netPtToAdd * (ONE + totalSy * pyIndex / totalPt) = netPtFromSwap * ONE - netSyToSwap * pyIndex

        uint256 pyIndex = PYIndex.unwrap(index);
        uint256 netPtToAddNumerator = (netPtFromSwap * Math.ONE - netSyToSwap * pyIndex);
        uint256 netPtToAddDenominator = (Math.ONE +
            (state.totalSy.Uint() * pyIndex) /
            state.totalPt.Uint());
        uint256 netPtToAdd = netPtToAddNumerator / netPtToAddDenominator;

        netYtIn = netPtFromSwap - netPtToAdd; // = netPtRedeemSy

        IPMarket(market).swapSyForExactPt(
            address(this),
            netPtFromSwap,
            _encodeAddLiqFromYt(netYtIn)
        );

        uint256 netSyFromPy = index.assetToSy(netYtIn);
        uint256 netSyToAdd = netSyFromPy - netSyToSwap;

        (netLpOut, , ) = IPMarket(market).mint(address(this), netSyToAdd, netPtToAdd);
        if (netLpOut < minLpOut) revert Errors.BotInsufficientLpOut(netLpOut, minLpOut);
    }

    /// @dev Behaves like PendleRouter's removeLiquidityDualSyAndPt then swapExactPtForYt
    /// @param guessTotalPtToSwap Same like for PendleRouter's swapExactPtForYt
    function _removeLiqToYt(
        uint256 netLpToRemove,
        ApproxParams memory guessTotalPtToSwap,
        uint256 minYtOut
    ) internal returns (uint256 netYtOut, uint256 totalPtToSwap) {
        _transferOut(market, market, netLpToRemove);
        (uint256 netSyFromLp, uint256 netPtFromLp) = IPMarket(market).burn(
            YT,
            market,
            netLpToRemove
        ); // SY goes to YT to mint PY, PT goes to market to swap

        MarketState memory state = IPMarket(market).readState(address(this));
        PYIndex index = IPYieldToken(YT).newIndex();

        uint256 netPtFromSy = index.syToAsset(netSyFromLp);

        uint256 netYtFromSwap;
        (netYtFromSwap, totalPtToSwap, ) = state.approxSwapExactPtForYt(
            index,
            netPtFromLp + netPtFromSy,
            block.timestamp,
            guessTotalPtToSwap
        );

        netYtOut = netYtFromSwap + netPtFromSy;
        if (netYtOut < minYtOut) revert Errors.BotInsufficientYtOut(netYtOut, minYtOut);

        IPMarket(market).swapExactPtForSy(YT, totalPtToSwap, _encodeRemoveLiqToYt(minYtOut)); // SY goes to YT to mint PY
    }
}

