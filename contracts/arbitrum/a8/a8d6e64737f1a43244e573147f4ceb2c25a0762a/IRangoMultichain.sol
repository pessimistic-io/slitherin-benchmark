// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./LibSwapper.sol";

/// @title An interface to RangoMultichain.sol contract to improve type hinting
/// @author Uchiha Sasuke
interface IRangoMultichain {
    enum MultichainBridgeType {OUT, OUT_UNDERLYING, OUT_NATIVE}

    /// @notice The request object for MultichainOrg bridge call
    /// @param actionType The type of bridge action which indicates the name of the function of MultichainOrg contract to be called
    /// @param underlyingToken For actionType = OUT_UNDERLYING, it's the address of the underlying token
    /// @param multichainRouter Address of MultichainOrg contract on the current chain
    /// @param receiverAddress The address of end-user on the destination
    /// @param receiverChainID The network id of destination chain
    struct MultichainBridgeRequest {
        IRangoMultichain.MultichainBridgeType actionType;
        address underlyingToken;
        address multichainRouter;
        address receiverAddress;
        uint receiverChainID;
    }

    function multichainSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoMultichain.MultichainBridgeRequest memory bridgeRequest
    ) external payable;

    function multichainBridge(
        IRangoMultichain.MultichainBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}
