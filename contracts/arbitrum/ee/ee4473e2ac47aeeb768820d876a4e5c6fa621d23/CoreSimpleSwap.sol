// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { ICoreSimpleSwapV1 } from "./ICoreSimpleSwapV1.sol";
import { DefinitiveAssets, IERC20 } from "./DefinitiveAssets.sol";
import { Context } from "./Context.sol";
import { CallUtils } from "./BubbleReverts.sol";
import { DefinitiveConstants } from "./DefinitiveConstants.sol";
import {     InvalidSwapHandler,     InsufficientSwapTokenBalance,     SwapTokenIsOutputToken,     InvalidOutputToken,     InvalidReportedOutputAmount,     InvalidExecutedOutputAmount } from "./DefinitiveErrors.sol";

struct CoreSimpleSwapConfig {
    address[] swapHandlers;
}

struct SwapPayload {
    address handler;
    uint256 amount; // set 0 for maximum available balance
    address swapToken;
    uint256 amountOutMin;
    bool isDelegate;
    bytes handlerCalldata;
    bytes signature;
}

abstract contract CoreSimpleSwap is ICoreSimpleSwapV1, Context {
    using DefinitiveAssets for IERC20;

    /// @dev handler contract => enabled
    mapping(address => bool) public _swapHandlers;

    constructor(CoreSimpleSwapConfig memory coreSimpleSwapConfig) {
        uint256 handlersLength = coreSimpleSwapConfig.swapHandlers.length;
        for (uint256 i; i < handlersLength; ) {
            _swapHandlers[coreSimpleSwapConfig.swapHandlers[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    function enableSwapHandlers(address[] memory swapHandlers) public virtual;

    function disableSwapHandlers(address[] memory swapHandlers) public virtual;

    function _updateSwapHandlers(address[] memory swapHandlers, bool enabled) internal {
        uint256 swapHandlersLength = swapHandlers.length;
        for (uint256 i; i < swapHandlersLength; ) {
            _swapHandlers[swapHandlers[i]] = enabled;
            emit SwapHandlerUpdate(_msgSender(), swapHandlers[i], enabled);
            unchecked {
                ++i;
            }
        }
    }

    function swap(
        SwapPayload[] memory payloads,
        address outputToken,
        uint256 amountOutMin,
        uint256 feePct
    ) external virtual returns (uint256 outputAmount);

    function _swap(
        SwapPayload[] memory payloads,
        address expectedOutputToken
    ) internal returns (uint256[] memory inputTokenAmounts, uint256 outputTokenAmount) {
        uint256 payloadsLength = payloads.length;
        inputTokenAmounts = new uint256[](payloadsLength);
        uint256 outputTokenBalanceStart = DefinitiveAssets.getBalance(expectedOutputToken);

        for (uint256 i; i < payloadsLength; ) {
            SwapPayload memory payload = payloads[i];

            if (!_swapHandlers[payload.handler]) {
                revert InvalidSwapHandler();
            }

            if (expectedOutputToken == payload.swapToken) {
                revert SwapTokenIsOutputToken();
            }

            uint256 outputTokenBalanceBefore = DefinitiveAssets.getBalance(expectedOutputToken);
            inputTokenAmounts[i] = DefinitiveAssets.getBalance(payload.swapToken);

            (uint256 _outputAmount, address _outputToken) = _processSwap(payload, expectedOutputToken);

            if (_outputToken != expectedOutputToken) {
                revert InvalidOutputToken();
            }
            if (_outputAmount < payload.amountOutMin) {
                revert InvalidReportedOutputAmount();
            }
            uint256 outputTokenBalanceAfter = DefinitiveAssets.getBalance(expectedOutputToken);

            if ((outputTokenBalanceAfter - outputTokenBalanceBefore) < payload.amountOutMin) {
                revert InvalidExecutedOutputAmount();
            }

            // Update `inputTokenAmounts` to reflect the amount of tokens actually swapped
            inputTokenAmounts[i] -= DefinitiveAssets.getBalance(payload.swapToken);
            unchecked {
                ++i;
            }
        }

        outputTokenAmount = DefinitiveAssets.getBalance(expectedOutputToken) - outputTokenBalanceStart;
    }

    function _processSwap(SwapPayload memory payload, address expectedOutputToken) private returns (uint256, address) {
        // Override payload.amount with validated amount
        payload.amount = _getValidatedPayloadAmount(payload);

        bytes memory _calldata = _getEncodedSwapHandlerCalldata(payload, expectedOutputToken, payload.isDelegate);

        bool _success;
        bytes memory _returnBytes;
        if (payload.isDelegate) {
            // slither-disable-next-line controlled-delegatecall
            (_success, _returnBytes) = payload.handler.delegatecall(_calldata);
        } else {
            _prepareAssetsForNonDelegateHandlerCall(payload, payload.amount);
            (_success, _returnBytes) = payload.handler.call(_calldata);
        }

        if (!_success) {
            CallUtils.revertFromReturnedData(_returnBytes);
        }

        return abi.decode(_returnBytes, (uint256, address));
    }

    function _getEncodedSwapHandlerCalldata(
        SwapPayload memory payload,
        address expectedOutputToken,
        bool isDelegateCall
    ) internal pure virtual returns (bytes memory);

    function _getValidatedPayloadAmount(SwapPayload memory payload) private view returns (uint256 amount) {
        uint256 balance = DefinitiveAssets.getBalance(payload.swapToken);

        // Ensure balance > 0
        DefinitiveAssets.validateAmount(balance);

        amount = payload.amount;

        if (amount != 0 && balance < amount) {
            revert InsufficientSwapTokenBalance();
        }

        // maximum available balance if amount == 0
        if (amount == 0) {
            return balance;
        }
    }

    function _prepareAssetsForNonDelegateHandlerCall(SwapPayload memory payload, uint256 amount) private {
        if (payload.swapToken == DefinitiveConstants.NATIVE_ASSET_ADDRESS) {
            // Send ETH to handler
            DefinitiveAssets.safeTransferETH(payable(payload.handler), amount);
        } else {
            IERC20(payload.swapToken).resetAndSafeIncreaseAllowance(address(this), payload.handler, amount);
        }
    }
}

