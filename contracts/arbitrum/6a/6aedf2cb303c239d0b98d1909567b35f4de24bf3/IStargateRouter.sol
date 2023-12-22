// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { LayerZeroTxConfig } from "./StargateRouterStructs.sol";

interface IStargateRouter {
    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        LayerZeroTxConfig memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    ) external payable;

    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        LayerZeroTxConfig memory _lzTxParams
    ) external view returns (uint256, uint256);
}

