// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { LibSwap } from "./LibSwap.sol";
import { LibAsset } from "./LibAsset.sol";
import { LibAllowList } from "./LibAllowList.sol";
import { LibUtil } from "./LibUtil.sol";
import { CumulativeSlippageTooHigh, ContractCallNotAllowed } from "./GenericErrors.sol";
import { IWETH } from "./IWETH.sol";
import { LibFeeCollector } from "./LibFeeCollector.sol";

error EmptySwapPath();
error IncorrectMsgValue();
error IncorrectWETH();

contract Swapper {
    function _swap(
        uint256 _fromAmount,
        uint256 _minAmount,
        address _weth,
        LibSwap.SwapData[] calldata _swaps,
        uint256 _nativeReserve,
        address _partner
    ) internal returns (uint256) {
        uint256 numSwaps = _swaps.length;
        uint256 fromAmount = _fromAmount;
        address fromToken = _swaps[0].fromToken;

        if (numSwaps == 0) revert EmptySwapPath();

        address lastToken = _swaps[numSwaps - 1].toToken;
        uint256 initialBalance = LibAsset.getOwnBalance(lastToken);

        if (LibAsset.isNativeAsset(lastToken)) {
            initialBalance -= msg.value;
        }

        if (LibAsset.isNativeAsset(fromToken)) {
            if (LibUtil.isZeroAddress(_weth)) revert IncorrectWETH();
            if (fromAmount + _nativeReserve != msg.value) revert IncorrectMsgValue();
            IWETH(_weth).deposit{value: fromAmount}();
            fromToken = _weth;
        } else {
            LibAsset.depositAsset(fromToken, fromAmount);
        }

        fromAmount = LibFeeCollector.takeFromTokenFee(fromAmount, fromToken, _partner);

        _executeSwaps(_swaps, fromAmount, _weth);

        uint256 receivedAmount;
        if (LibAsset.isNativeAsset(lastToken)) {
            receivedAmount = LibAsset.getOwnBalance(_weth) - initialBalance;
            IWETH(_weth).withdraw(receivedAmount);
        } else {
            receivedAmount = LibAsset.getOwnBalance(lastToken) - initialBalance; 
        }

        if (receivedAmount < _minAmount) revert CumulativeSlippageTooHigh(_minAmount, receivedAmount);

        return receivedAmount;
    }

    function _executeSwaps(LibSwap.SwapData[] calldata _swaps, uint256 _fromAmount, address _weth) internal {
        uint256 numSwaps = _swaps.length;
        for (uint256 i = 0; i < numSwaps; ) {
            LibSwap.SwapData calldata currentSwap = _swaps[i];

            if (
                !((LibAsset.isNativeAsset(currentSwap.fromToken) ||
                    LibAllowList.isContractAllowed(currentSwap.adapter)) &&
                    LibAllowList.isContractAllowed(currentSwap.adapter)
                )
            ) revert ContractCallNotAllowed();

            uint256 receivedAmount;
            uint256 fromAmount = i > 0 
                ? receivedAmount
                : _fromAmount;

            receivedAmount = LibSwap.swap(
                fromAmount,
                currentSwap,
                _weth
                // LibAsset.isNativeAsset(currentSwap.fromToken) ? _weth : address(0),
            );

            unchecked {
                ++i;
            }
        }
    }
}
