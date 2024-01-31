// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Interchain.sol";
import "./LibSwapper.sol";

/// @title IRangoOptimism
/// @author AMA
interface IRangoOptimism {
    /// @notice The request object for Optimism bridge call
    struct OptimismBridgeRequest {
        address receiver;
        address l2TokenAddress;
        uint32 l2Gas;
        bool isSynth;
    }

    function optimismBridge(
        IRangoOptimism.OptimismBridgeRequest memory bridgeRequest,
        address fromToken,
        uint256 amount
    ) external payable;

    function optimismBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoOptimism.OptimismBridgeRequest memory bridgeRequest
    ) external payable;
}
