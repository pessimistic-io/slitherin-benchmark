// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./IStargateRouter.sol";
import "./Interchain.sol";
import "./LibSwapper.sol";

/// @title An interface to interact with RangoStargateFacet
/// @author Uchiha Sasuke
interface IRangoStargate {
    enum StargateBridgeType {TRANSFER, TRANSFER_WITH_MESSAGE}

    struct StargateRequest {
        StargateBridgeType bridgeType;
        uint16 dstChainId;
        uint256 srcPoolId;
        uint256 dstPoolId;
        address payable refundAddress;
        uint256 minAmountLD;

        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;

        bytes to;
        uint stgFee;

        Interchain.RangoInterChainMessage payload;
    }

    function stargateSwap(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoStargate.StargateRequest memory stargateRequest
    ) external payable;

    function stargateSwap(
        IRangoStargate.StargateRequest memory stargateRequest,
        address token,
        uint256 amount
    ) external payable;
}
