// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { SwapPayload } from "./CoreSimpleSwap.sol";

interface ICoreSimpleSwapV1 {
    event SwapHandlerUpdate(address actor, address swapHandler, bool isEnabled);
    event SwapHandled(
        address[] swapTokens,
        uint256[] swapAmounts,
        address outputToken,
        uint256 outputAmount,
        uint256 feeAmount
    );

    function enableSwapHandlers(address[] memory swapHandlers) external;

    function disableSwapHandlers(address[] memory swapHandlers) external;

    function swap(
        SwapPayload[] memory payloads,
        address outputToken,
        uint256 amountOutMin,
        uint256 feePct
    ) external returns (uint256 outputAmount);
}

