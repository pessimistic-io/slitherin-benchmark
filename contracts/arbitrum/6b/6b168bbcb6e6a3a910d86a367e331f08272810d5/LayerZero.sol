// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {RemoteMessaging} from "./RemoteMessaging.sol";

interface ILayerZeroEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external view returns (uint nativeFee, uint zroFee);
}

interface ILayerZeroReceiver {
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external;
}

abstract contract LayerZero is ILayerZeroReceiver, RemoteMessaging {
    ILayerZeroEndpoint immutable lzEndpoint;
    uint16 immutable lzRemoteChainId;

    constructor(address lzEndpoint_, uint16 lzRemoteChainId_) {
        lzEndpoint = ILayerZeroEndpoint(lzEndpoint_);
        lzRemoteChainId = lzRemoteChainId_;
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64,
        bytes calldata _payload
    ) external {
        require(_srcChainId == lzRemoteChainId);
        require(msg.sender == address(lzEndpoint));
        require(
            keccak256(_srcAddress) ==
                keccak256(abi.encodePacked(address(this), address(this)))
        );
        _processPayload(_payload);
    }

    function _sendMessage(
        bytes calldata instructionData,
        bytes memory payload
    ) internal override {
        (address lzPaymentAddress, bytes memory lzAdapterParams) = abi.decode(
            instructionData,
            (address, bytes)
        );

        ILayerZeroEndpoint(lzEndpoint).send{value: msg.value}(
            lzRemoteChainId,
            abi.encodePacked(address(this), address(this)),
            payload,
            payable(tx.origin),
            lzPaymentAddress,
            lzAdapterParams
        );
    }

    function quoteLayerZeroFee(
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        (nativeFee, zroFee) = lzEndpoint.estimateFees(
            lzRemoteChainId,
            address(this),
            _encodePayload(address(1), address(1), 1), // estimateFees use only _payload.length
            _payInZRO,
            _adapterParam
        );
    }
}

