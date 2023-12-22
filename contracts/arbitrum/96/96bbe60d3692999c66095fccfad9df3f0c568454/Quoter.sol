// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { LibSwap } from "./LibSwap.sol";
import { LibQuote } from "./LibQuote.sol";
import { LibAsset } from "./LibAsset.sol";
import { LibAllowList } from "./LibAllowList.sol";
import { LibUtil } from "./LibUtil.sol";
import { CumulativeSlippageTooHigh, ContractCallNotAllowed } from "./GenericErrors.sol";
import { IWETH } from "./IWETH.sol";
import { LibFeeCollector } from "./LibFeeCollector.sol";

error EmptySwapPath();
error IncorrectMsgValue();
error IncorrectWETH();

contract Quoter {
    function _quote(
        uint256 _fromAmount,
        uint256,
        address _weth,
        LibSwap.SwapData[] calldata _swaps,
        uint256,
        address
    ) internal returns (uint256 receivedAmount) {
        uint256 numSwaps = _swaps.length;
        uint256 fromAmount = _fromAmount;
        address fromToken = _swaps[0].fromToken;

        if (numSwaps == 0) revert EmptySwapPath();

        if (LibAsset.isNativeAsset(fromToken)) {
            if (LibUtil.isZeroAddress(_weth)) revert IncorrectWETH();
            fromToken = _weth;
        } 

        uint256 fee = LibFeeCollector.getMainFee();
        fromAmount = fromAmount * (10000 - fee) / 10000;

        receivedAmount = _executeQuotes(_swaps, fromAmount, _weth);
        return receivedAmount;
    }

    function _executeQuotes(LibSwap.SwapData[] calldata _swaps, uint256 _fromAmount, address _weth) internal returns(uint256 receivedAmount) {
        uint256 numSwaps = _swaps.length;
        for (uint256 i = 0; i < numSwaps; ) {
            LibSwap.SwapData calldata currentSwap = _swaps[i];
            if (
                !((LibAsset.isNativeAsset(currentSwap.fromToken) ||
                    LibAllowList.isContractAllowed(currentSwap.adapter)) &&
                    LibAllowList.isContractAllowed(currentSwap.adapter)
                )
            ) revert ContractCallNotAllowed();

            uint256 fromAmount = i > 0 
                ? receivedAmount
                : _fromAmount;

            receivedAmount = LibQuote.quote(
                fromAmount,
                currentSwap,
                _weth
            );

            unchecked {
                ++i;
            }
        }
    }
}
