// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { BaseFees } from "./BaseFees.sol";
import { CoreSimpleSwap, CoreSimpleSwapConfig, SwapPayload } from "./CoreSimpleSwap.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { DefinitiveConstants } from "./DefinitiveConstants.sol";
import { InvalidFeePercent, SlippageExceeded } from "./DefinitiveErrors.sol";
import { ICoreSwapHandlerV1 } from "./ICoreSwapHandlerV1.sol";

abstract contract BaseSimpleSwap is BaseFees, CoreSimpleSwap, ReentrancyGuard {
    constructor(CoreSimpleSwapConfig memory coreSimpleSwapConfig) CoreSimpleSwap(coreSimpleSwapConfig) {}

    function enableSwapHandlers(address[] memory swapHandlers) public override onlyClientAdmin stopGuarded {
        _updateSwapHandlers(swapHandlers, true);
    }

    function disableSwapHandlers(address[] memory swapHandlers) public override onlyAdmins {
        _updateSwapHandlers(swapHandlers, false);
    }

    function swap(
        SwapPayload[] memory payloads,
        address outputToken,
        uint256 amountOutMin,
        uint256 feePct
    ) public override onlyDefinitive nonReentrant stopGuarded returns (uint256) {
        if (feePct > DefinitiveConstants.MAX_FEE_PCT) {
            revert InvalidFeePercent();
        }

        (uint256[] memory inputAmounts, uint256 outputAmount) = _swap(payloads, outputToken);
        if (outputAmount < amountOutMin) {
            revert SlippageExceeded(outputAmount, amountOutMin);
        }

        address[] memory swapTokens = new address[](payloads.length);
        uint256 swapTokensLength = swapTokens.length;
        for (uint256 i; i < swapTokensLength; ) {
            swapTokens[i] = payloads[i].swapToken;
            unchecked {
                ++i;
            }
        }

        uint256 feeAmount;
        if (FEE_ACCOUNT != address(0) && outputAmount > 0 && feePct > 0) {
            feeAmount = _handleFeesOnAmount(outputToken, outputAmount, feePct);
        }
        emit SwapHandled(swapTokens, inputAmounts, outputToken, outputAmount, feeAmount);

        return outputAmount;
    }

    function _getEncodedSwapHandlerCalldata(
        SwapPayload memory payload,
        address expectedOutputToken,
        bool isDelegateCall
    ) internal pure override returns (bytes memory) {
        bytes4 selector = isDelegateCall
            ? ICoreSwapHandlerV1.swapDelegate.selector
            : ICoreSwapHandlerV1.swapCall.selector;
        ICoreSwapHandlerV1.SwapParams memory _params = ICoreSwapHandlerV1.SwapParams({
            inputAssetAddress: payload.swapToken,
            inputAmount: payload.amount,
            outputAssetAddress: expectedOutputToken,
            minOutputAmount: payload.amountOutMin,
            data: payload.handlerCalldata,
            signature: payload.signature
        });
        return abi.encodeWithSelector(selector, _params);
    }
}

