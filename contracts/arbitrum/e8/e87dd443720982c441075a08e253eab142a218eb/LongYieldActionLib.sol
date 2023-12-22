// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

// import "../base/TradingBotBase.sol";
import "./MarketApproxLib.sol";
import "./IPAllAction.sol";
import "./IPMarket.sol";
import "./IBotDecisionHelper.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

// This external library aims to implements all the action logics for LongYieldTradingBot
// No technical perference. Only purpose is to smaller the bytecode size of LongYieldTradingBot.sol

library LongYieldActionLib {
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;
    using MarketMathCore for MarketState;
    using MarketApproxPtInLib for MarketState;
    using Math for int256;
    using SafeERC20 for IERC20;

    bytes internal constant EMPTY_BYTES = abi.encode();

    address internal constant ROUTER = 0x0000000001E4ef00d069e71d6bA041b0A16F7eA0;

    function liquidateLpToSy(
        address market,
        uint256 netLpToRemove,
        uint256 minSyOut
    ) public returns (uint256 netSyOut) {
        (uint256 netSyFromLp, uint256 netPtOut) = IPAllAction(ROUTER).removeLiquidityDualSyAndPt(
            address(this),
            market,
            netLpToRemove,
            0,
            0
        );

        (uint256 netSyFromPt, ) = IPAllAction(ROUTER).swapExactPtForSy(
            address(this),
            market,
            netPtOut,
            0
        );

        netSyOut = netSyFromLp + netSyFromPt;
        require(netSyOut > minSyOut, "liquidateLpToSy: insufficient sy out");
    }

    function removeLiquidityToSy(
        address market,
        uint256 netLpToRemove,
        uint256 minSyOut
    ) public returns (uint256 netSyOut) {
        (uint256 netSyFromLp, uint256 netPtOut) = IPAllAction(ROUTER).removeLiquidityDualSyAndPt(
            address(this),
            market,
            netLpToRemove,
            0,
            0
        );

        (, , IPYieldToken YT) = IPMarket(market).readTokens();
        uint256 netSyFromRedeemPY = IPAllAction(ROUTER).redeemPyToSy(
            address(this),
            address(YT),
            Math.min(netPtOut, YT.balanceOf(address(this))),
            0
        );

        netSyOut = netSyFromLp + netSyFromRedeemPY;
        require(netSyOut > minSyOut, "removeLiquidityToSy: insufficient sy out");
    }

    function swapYtToSy(
        address market,
        uint256 netYtIn,
        uint256 minSyOut
    ) public returns (uint256 netSyOut) {
        (netSyOut, ) = IPAllAction(ROUTER).swapExactYtForSy(
            address(this),
            market,
            netYtIn,
            minSyOut
        );
    }

    function addLiqKeepYt(
        address market,
        uint256 netSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) public returns (uint256 /*netLpOut*/, uint256 /*netYtOut*/) {
        return
            IPAllAction(ROUTER).addLiquiditySingleSyKeepYt(
                address(this),
                market,
                netSyIn,
                minLpOut,
                minYtOut
            );
    }

    function addLiqFromYt(
        address market,
        uint256 netPtFromSwap,
        uint256 minLpOut
    ) public returns (uint256 netLpOut, uint256 netYtIn) {
        MarketState memory state = IPMarket(market).readState(address(this));
        (, , IPYieldToken YT) = IPMarket(market).readTokens();

        PYIndex index = YT.newIndex();

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
    function removeLiqToYt(
        address market,
        uint256 netLpToRemove,
        ApproxParams memory guessTotalPtToSwap,
        uint256 minYtOut
    ) public returns (uint256 netYtOut, uint256 totalPtToSwap) {
        IERC20(market).safeTransfer(market, netLpToRemove);
        (, , IPYieldToken YT) = IPMarket(market).readTokens();
        (uint256 netSyFromLp, uint256 netPtFromLp) = IPMarket(market).burn(
            address(YT),
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

        IPMarket(market).swapExactPtForSy(
            address(YT),
            totalPtToSwap,
            _encodeRemoveLiqToYt(minYtOut)
        ); // SY goes to YT to mint PY
    }

    /*///////////////////////////////////////////////////////////////
                               Callback
    //////////////////////////////////////////////////////////////*/

    function swapCallback(
        address market,
        int256 ptToAccount,
        int256 syToAccount,
        bytes calldata data
    ) public {
        TradeActionType swapType = _getActionType(data);

        (, IPPrincipalToken PT, IPYieldToken YT) = IPMarket(market).readTokens();

        if (swapType == TradeActionType.AddLiqFromYt) {
            _callbackAddLiqFromYt(
                market,
                address(PT),
                address(YT),
                ptToAccount,
                syToAccount,
                data
            );
        } else if (swapType == TradeActionType.RemoveLiqToYt) {
            _callbackRemoveLiqToYt(
                market,
                address(PT),
                address(YT),
                ptToAccount,
                syToAccount,
                data
            );
        } else {
            assert(false);
        }
    }

    /// ------------------------------------------------------------
    /// AddLiqFromYt
    /// ------------------------------------------------------------

    function _callbackAddLiqFromYt(
        address market,
        address PT,
        address YT,
        int256 ptToAccount,
        int256 /*syToAccount*/,
        bytes calldata data
    ) internal {
        uint256 netPyRedeemSy = _decodeAddLiqFromYt(data);
        IERC20(PT).safeTransfer(address(YT), netPyRedeemSy);

        bool needToBurnYt = (!IPYieldToken(YT).isExpired());
        if (needToBurnYt) IERC20(YT).safeTransfer(YT, netPyRedeemSy);

        IPYieldToken(YT).redeemPY(market); // all SY goes to market to repay and mint LP
        IERC20(PT).safeTransfer(market, ptToAccount.Uint() - netPyRedeemSy); // remaining PT goes to market to mint LP
    }

    function _decodeAddLiqFromYt(
        bytes calldata data
    ) internal pure returns (uint256 netPyRedeemSy) {
        assembly {
            // first 32 bytes is ActionType
            netPyRedeemSy := calldataload(add(data.offset, 32))
        }
    }

    /// ------------------------------------------------------------
    /// RemoveLiqToYt
    /// ------------------------------------------------------------

    function _callbackRemoveLiqToYt(
        address market,
        address /*PT*/,
        address YT,
        int256 /*ptToAccount*/,
        int256 /*syToAccount*/,
        bytes calldata data
    ) internal {
        uint256 minYtOut = _decodeRemoveLiqToYt(data);

        uint256 netYtOut = IPYieldToken(YT).mintPY(market, address(this)); // PT goes to market to repay
        if (netYtOut < minYtOut) revert Errors.BotInsufficientYtOut(netYtOut, minYtOut); // 2nd check
    }

    /// ------------------------------------------------------------
    /// Misc functions
    /// ------------------------------------------------------------

    function _getActionType(
        bytes calldata data
    ) internal pure returns (TradeActionType actionType) {
        assembly {
            actionType := calldataload(data.offset)
        }
    }

    function _decodeRemoveLiqToYt(bytes calldata data) internal pure returns (uint256 minYtOut) {
        assembly {
            // first 32 bytes is ActionType
            minYtOut := calldataload(add(data.offset, 32))
        }
    }

    function _encodeRemoveLiqToYt(uint256 minYtOut) internal pure returns (bytes memory res) {
        res = new bytes(64);
        uint256 actionType = uint256(TradeActionType.RemoveLiqToYt);

        assembly {
            mstore(add(res, 32), actionType)
            mstore(add(res, 64), minYtOut)
        }
    }

    function _encodeAddLiqFromYt(uint256 netPyRedeemSy) internal pure returns (bytes memory res) {
        res = new bytes(64);
        uint256 actionType = uint256(TradeActionType.AddLiqFromYt);

        assembly {
            mstore(add(res, 32), actionType)
            mstore(add(res, 64), netPyRedeemSy)
        }
    }
}

