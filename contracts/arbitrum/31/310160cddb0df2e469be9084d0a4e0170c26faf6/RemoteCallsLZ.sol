// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {RemoteCalls} from "./RemoteCalls.sol";
import {ILayerZeroEndpoint} from "./ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "./ILayerZeroReceiver.sol";

contract RemoteCallsLZ is ILayerZeroReceiver, RemoteCalls {
    // version + value - https://layerzero.gitbook.io/docs/evm-guides/advanced/relayer-adapter-parameters
    uint256 constant MIN_ADAPTER_PARAMS_LENGTH = 34;

    ILayerZeroEndpoint immutable LZ_ENDPOINT;
    uint16 immutable LZ_REMOTE_CHAIN_ID;
    uint256 immutable MIN_DST_GAS;

    error InvalidAdapterParams();

    constructor(address lzEndpoint, uint16 lzRemoteChainId, uint256 minDstGas) {
        LZ_ENDPOINT = ILayerZeroEndpoint(lzEndpoint);
        LZ_REMOTE_CHAIN_ID = lzRemoteChainId;
        MIN_DST_GAS = minDstGas;
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64,
        bytes calldata _payload
    ) external {
        if (
            _srcChainId != LZ_REMOTE_CHAIN_ID ||
            msg.sender != address(LZ_ENDPOINT) ||
            keccak256(_srcAddress) !=
            keccak256(abi.encodePacked(address(this), address(this)))
        ) revert RemoteCallFailed();

        _finishRemoteCall(_payload);
    }

    function quoteLayerZeroFee(
        bytes calldata calldata_,
        bool payInZRO,
        bytes calldata lzAdapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        (nativeFee, zroFee) = LZ_ENDPOINT.estimateFees({
            _dstChainId: LZ_REMOTE_CHAIN_ID,
            _userApplication: address(this),
            _payload: calldata_,
            _payInZRO: payInZRO,
            _adapterParam: lzAdapterParams
        });
    }

    function remoteCallType() external pure override returns (RemoteCallsType) {
        return RemoteCallsType.LZ;
    }

    function _remoteCall(
        bytes memory calldata_,
        bytes calldata bridgeParams
    ) internal override {
        (address lzPaymentAddress, bytes memory lzAdapterParams) = abi.decode(
            bridgeParams,
            (address, bytes)
        );

        if (lzAdapterParams.length < MIN_ADAPTER_PARAMS_LENGTH) {
            revert InvalidAdapterParams();
        } else {
            uint256 gasLimit;
            assembly {
                gasLimit := mload(
                    add(lzAdapterParams, MIN_ADAPTER_PARAMS_LENGTH)
                )
            }
            if (gasLimit < MIN_DST_GAS) revert InvalidAdapterParams();
        }

        // solhint-disable-next-line check-send-result
        ILayerZeroEndpoint(LZ_ENDPOINT).send{value: msg.value}({
            _dstChainId: LZ_REMOTE_CHAIN_ID,
            _destination: abi.encodePacked(address(this), address(this)),
            _payload: calldata_,
            _refundAddress: payable(tx.origin), // solhint-disable-line avoid-tx-origin
            _zroPaymentAddress: lzPaymentAddress,
            _adapterParams: lzAdapterParams
        });
    }
}

