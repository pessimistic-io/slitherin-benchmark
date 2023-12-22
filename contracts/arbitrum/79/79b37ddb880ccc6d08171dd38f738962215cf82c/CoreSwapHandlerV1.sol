// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import {     InvalidExecutedOutputAmount,     InvalidMsgValue,     InvalidSwapInputAmount } from "./DefinitiveErrors.sol";
import { DefinitiveConstants } from "./DefinitiveConstants.sol";
import { DefinitiveAssets, IERC20 } from "./DefinitiveAssets.sol";
import { Context } from "./Context.sol";
import { ICoreSwapHandlerV1 } from "./ICoreSwapHandlerV1.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

abstract contract CoreSwapHandlerV1 is ICoreSwapHandlerV1, Context, ReentrancyGuard {
    using DefinitiveAssets for IERC20;

    function swapCall(SwapParams calldata params) external payable nonReentrant returns (uint256, address) {
        return _swapCall(params, false /* enforceAllowedPools */);
    }

    function swapDelegate(SwapParams calldata params) external payable nonReentrant returns (uint256, address) {
        return _swapDelegate(params, false /* enforceAllowedPools */);
    }

    function swapUsingValidatedPathCall(
        SwapParams calldata params
    ) external payable nonReentrant returns (uint256, address) {
        return _swapCall(params, true /* enforceAllowedPools */);
    }

    function _swapCall(
        SwapParams memory params,
        bool enforceAllowedPools
    ) private returns (uint256 amountOut, address) {
        bool isInputAddressNativeAsset = params.inputAssetAddress == DefinitiveConstants.NATIVE_ASSET_ADDRESS;
        uint256 rawInputAmount = params.inputAmount;

        // Calls to swap native assets must provide a non-zero input amount
        if (isInputAddressNativeAsset && rawInputAmount == 0) {
            revert InvalidSwapInputAmount();
        }

        // Calls to swap native assets must match the input amount and msg.value
        if (isInputAddressNativeAsset && rawInputAmount != msg.value) {
            revert InvalidMsgValue();
        }

        // Calls to swap non-native assets must have msg.value equal to 0
        if (!isInputAddressNativeAsset && msg.value != 0) {
            revert InvalidMsgValue();
        }

        // Update SwapParams with parsed input amount
        params.inputAmount = rawInputAmount > 0 ? rawInputAmount : _getTokenAllowance(params.inputAssetAddress);

        if (params.inputAssetAddress != DefinitiveConstants.NATIVE_ASSET_ADDRESS) {
            IERC20(params.inputAssetAddress).safeTransferFrom(_msgSender(), address(this), params.inputAmount);
        }

        _validateSwap(params);
        _validatePools(params, enforceAllowedPools);

        (amountOut, ) = _swap(params);

        if (params.outputAssetAddress == DefinitiveConstants.NATIVE_ASSET_ADDRESS) {
            DefinitiveAssets.safeTransferETH(payable(_msgSender()), amountOut);
        } else {
            IERC20(params.outputAssetAddress).safeTransfer(_msgSender(), amountOut);
        }

        return (amountOut, params.outputAssetAddress);
    }

    function _swapDelegate(SwapParams memory params, bool enforceAllowedPools) private returns (uint256, address) {
        uint256 rawInputAmount = params.inputAmount;
        uint256 parsedInputAmount = rawInputAmount > 0
            ? rawInputAmount
            : DefinitiveAssets.getBalance(params.inputAssetAddress);

        if (parsedInputAmount == 0) {
            revert InvalidSwapInputAmount();
        }
        // Update SwapParams with parsed input amount
        params.inputAmount = parsedInputAmount;

        _validateSwap(params);
        _validatePools(params, enforceAllowedPools);

        return _swap(params);
    }

    /**
     * @notice This method holds the logic for performing the swap.
     * @param params SwapParams
     */
    function _performSwap(SwapParams memory params) internal virtual;

    /**
     * @notice Method to confirm that the swap is using valid pools based on our criteria
     * @param params SwapParams
     * @param enforceAllowedPools boolean to determine if we should enforce allowed pools
     */
    function _validatePools(SwapParams memory params, bool enforceAllowedPools) internal virtual;

    /**
     * @notice Method to confirm that the swap parameters are valid for the third party
     * @param params SwapParams
     */
    function _validateSwap(SwapParams memory params) internal virtual;

    /**
     * @notice When `rawInputAmount` is 0, `swapCall` will use the allowance as the input amount
     * @param inputAssetAddress asset to swap from
     */
    function _getTokenAllowance(address inputAssetAddress) private view returns (uint256) {
        uint256 allowance = IERC20(inputAssetAddress).allowance(_msgSender(), address(this));

        if (allowance == 0) {
            revert InvalidSwapInputAmount();
        }

        return allowance;
    }

    /**
     * @notice Returns the address we need to approve in order to swap assets
     * @param data included with the swap method invocation
     */
    function _getSpenderAddress(bytes memory data) internal virtual returns (address);

    /**
     * @notice Internal swap logic that performs the swap and validates the output amount
     * @param params SwapParams
     * @return output amount and output asset address
     */
    function _swap(SwapParams memory params) private returns (uint256, address) {
        if (params.inputAssetAddress != DefinitiveConstants.NATIVE_ASSET_ADDRESS) {
            IERC20(params.inputAssetAddress).resetAndSafeIncreaseAllowance(
                address(this),
                _getSpenderAddress(params.data),
                params.inputAmount
            );
        }

        uint256 outputAmountDelta = DefinitiveAssets.getBalance(params.outputAssetAddress);

        _performSwap(params);

        outputAmountDelta = DefinitiveAssets.getBalance(params.outputAssetAddress) - outputAmountDelta;

        if (outputAmountDelta < params.minOutputAmount) {
            revert InvalidExecutedOutputAmount();
        }

        emit Swap(
            _msgSender(),
            params.inputAssetAddress,
            params.inputAmount,
            params.outputAssetAddress,
            outputAmountDelta
        );

        return (outputAmountDelta, params.outputAssetAddress);
    }
}

