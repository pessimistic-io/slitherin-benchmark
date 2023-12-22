// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./TradingBotBase.sol";

abstract contract ShortYieldActionHelper is TradingBotBase {
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;
    using MarketMathCore for MarketState;
    using MarketApproxPtInLib for MarketState;
    using Math for int256;

    bytes internal constant EMPTY_BYTES = abi.encode();

    function _mintPY(
        uint256 netSyIn,
        uint256 minPyOut
    ) internal returns (uint256 netPyOut) {
        return IPAllAction(router).mintPyFromSy(
            address(this),
            YT,
            netSyIn,
            minPyOut
        );
    }

    function _swapPtForYt(
        uint256 netPtToSwap,
        ApproxParams memory guessTotalPtToSwap,
        uint256 minYtOut
    ) internal returns (uint256 netYtOut) {
        (netYtOut, ) = IPAllAction(router).swapExactPtForYt(
            address(this),
            market,
            netPtToSwap,
            minYtOut,
            guessTotalPtToSwap
        );
    }

    function _swapYtForPt(
        uint256 netYtToSwap,
        ApproxParams memory guessTotalYtToSwap,
        uint256 minPtOut
    ) internal returns (uint256 netPtOut) {
        (netPtOut, ) = IPAllAction(router).swapExactYtForPt(
            address(this),
            market,
            netYtToSwap,
            minPtOut,
            guessTotalYtToSwap
        );
    }
}

