// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IPMarketSwapCallback.sol";
import "./BotDecisionHelper.sol";
import "./TradingBotBase.sol";

abstract contract BotActionCallback is TradingBotBase, IPMarketSwapCallback {
    using Math for int256;

    modifier onlyMarket(address caller) {
        if (caller != market) revert Errors.BotCallbackNotMarket(caller);
        _;
    }

    function swapCallback(
        int256 ptToAccount,
        int256 syToAccount,
        bytes calldata data
    ) external override onlyMarket(msg.sender) {
        ActionType swapType = _getActionType(data);
        if (swapType == ActionType.AddLiqFromYt) {
            _callbackAddLiqFromYt(ptToAccount, syToAccount, data);
        } else if (swapType == ActionType.RemoveLiqToYt) {
            _callbackRemoveLiqToYt(ptToAccount, syToAccount, data);
        } else {
            assert(false);
        }
    }

    /// ------------------------------------------------------------
    /// AddLiqFromYt
    /// ------------------------------------------------------------

    function _callbackAddLiqFromYt(
        int256 ptToAccount,
        int256 /*syToAccount*/,
        bytes calldata data
    ) internal {
        uint256 netPyRedeemSy = _decodeAddLiqFromYt(data);

        _transferOut(PT, YT, netPyRedeemSy);

        bool needToBurnYt = (!IPYieldToken(YT).isExpired());
        if (needToBurnYt) _transferOut(YT, YT, netPyRedeemSy);

        IPYieldToken(YT).redeemPY(market); // all SY goes to market to repay and mint LP

        _transferOut(PT, market, ptToAccount.Uint() - netPyRedeemSy); // remaining PT goes to market to mint LP
    }

    function _encodeAddLiqFromYt(uint256 netPyRedeemSy) internal pure returns (bytes memory res) {
        res = new bytes(64);
        uint256 actionType = uint256(ActionType.AddLiqFromYt);

        assembly {
            mstore(add(res, 32), actionType)
            mstore(add(res, 64), netPyRedeemSy)
        }
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
        int256 /*ptToAccount*/,
        int256 /*syToAccount*/,
        bytes calldata data
    ) internal {
        uint256 minYtOut = _decodeRemoveLiqToYt(data);

        uint256 netYtOut = IPYieldToken(YT).mintPY(market, address(this)); // PT goes to market to repay
        if (netYtOut < minYtOut) revert Errors.BotInsufficientYtOut(netYtOut, minYtOut); // 2nd check
    }

    function _encodeRemoveLiqToYt(uint256 minYtOut) internal pure returns (bytes memory res) {
        res = new bytes(64);
        uint256 actionType = uint256(ActionType.RemoveLiqToYt);

        assembly {
            mstore(add(res, 32), actionType)
            mstore(add(res, 64), minYtOut)
        }
    }

    function _decodeRemoveLiqToYt(bytes calldata data) internal pure returns (uint256 minYtOut) {
        assembly {
            // first 32 bytes is ActionType
            minYtOut := calldataload(add(data.offset, 32))
        }
    }

    /// ------------------------------------------------------------
    /// Misc functions
    /// ------------------------------------------------------------

    function _getActionType(bytes calldata data) internal pure returns (ActionType actionType) {
        assembly {
            actionType := calldataload(data.offset)
        }
    }
}

