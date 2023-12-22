// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {NonBlockingLZMultichain} from "./NonBlockingLZMultichain.sol";
import {SimpleFactory} from "./SimpleFactory.sol";
import "./BytesLib.sol";

contract MultiChainFactory is NonBlockingLZMultichain {
    using BytesLib for bytes;
    event LogAddMasterContract(uint256 indexed index, address master);

    event SetUseCustomAdapterParams(bool _useCustomAdapterParams);

    struct LzCallParams {
        address payable refundAddress;
        address zroPaymentAddress;
        bytes adapterParams;
    }

     // packet type
    uint8 public constant PT_DEPLOY_BYTECODE = 0;
    uint8 public constant PT_DEPLOY_PROXY = 1;
    uint8 public constant PT_DIRECT_CALL = 2;
    
    uint256 private BPS = 10_000;

    SimpleFactory public immutable factory;
    uint16 public immutable chainId;
    address[] public masterContracts;
    bool public useCustomAdapterParams;

    constructor (uint16 chainId_, SimpleFactory factory_, address _endpoint) NonBlockingLZMultichain(_endpoint) {
        factory = factory_;
        chainId = chainId_;
    }

    function addMasterContract (address mastercontract) external onlyOwner {
        uint length = masterContracts.length;
        masterContracts.push(mastercontract);
        emit LogAddMasterContract(length, mastercontract);
    }

    function _nonblockingLzReceiveAfterConfig(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 nonce, /*_nonce*/
        bytes memory _payload,
        uint8 payloadType,
        bool retry
    ) internal override {

        if (payloadType == PT_DEPLOY_BYTECODE) {
            _deployWithByteCode(_srcChainId, _srcAddress, nonce, _payload);
        } else if (payloadType == PT_DEPLOY_PROXY) {
            _deployProxy(_srcChainId, _srcAddress, nonce, _payload);
        } else if (payloadType == PT_DIRECT_CALL) {
            _directCall(_srcChainId, _srcAddress, nonce, _payload);
        } else {
            revert("MultiChainFactory: unknown packet type");
        }
    }

    /************************************************************************
    * public functions
    ************************************************************************/

    function _deployWithByteCode(uint16 _srcChainId, bytes memory, uint64, bytes memory _payload) internal returns (address clone) {
        (bytes memory deployData, bool useCreate2) = abi.decode(_payload, (bytes, bool));
        clone = factory.deployWithByteCode(deployData, useCreate2);
    }

    function _deployProxy(uint16 _srcChainId, bytes memory, uint64, bytes memory _payload) internal returns (address clone) {
        (uint256 index, bytes memory data) = abi.decode(_payload, (uint256, bytes));
        clone = factory.deploy(masterContracts[index], data, true);
    }

    function _directCall(uint16 _srcChainId, bytes memory, uint64, bytes memory _payload) internal returns (address clone) {
        (address to, bytes memory data) = abi.decode(_payload, (address, bytes));
        (bool success, ) =  to.call(data);
        if (!success) {
            // TODO: Add revert reason
            revert();
        }
    }

    function setUseCustomAdapterParams(bool _useCustomAdapterParams) public virtual onlyOwner {
        useCustomAdapterParams = _useCustomAdapterParams;
        emit SetUseCustomAdapterParams(_useCustomAdapterParams);
    }

    function sendMultiple(uint8[] memory sendTypes, bytes[] memory datas) external payable {
        for(uint i; i < sendTypes.length; i++) {
            bool success;
            if (sendTypes[i] == PT_DEPLOY_BYTECODE) {
                (success, ) = address(this).call(abi.encodePacked(this.sendDeployWithByteCode.selector, datas[i]));
            } else if (sendTypes[i] == PT_DEPLOY_PROXY) {
                (success, ) = address(this).call(abi.encodePacked(this.sendDeployWithProxy.selector, datas[i]));
            } else if (sendTypes[i] == PT_DIRECT_CALL) {
                (success, ) = address(this).call(abi.encodePacked(this.sendDirectCall.selector, datas[i]));
            } else {
                revert("MultiChainFactory: unknown packet type");
            }
            require(success, "MultiChainFactory: multi send failed");
        }
     }

    function sendDeployWithByteCode(uint16 _dstChainId, bytes memory deployData, bool useCreate2, uint64 _dstGasForCall, address payable _refundAddress, address _zroPaymentAddress, bytes memory _adapterParams) public payable {
        if (chainId == _dstChainId) {
            _deployWithByteCode(_dstChainId, bytes(""), 0, abi.encode(deployData, useCreate2));
            return;
        }
        _checkAdapterParams(_dstChainId, PT_DEPLOY_BYTECODE, _adapterParams, _dstGasForCall);

        bytes memory lzPayload = abi.encode(PT_DEPLOY_BYTECODE, abi.encode(deployData, useCreate2));
        _lzSend(_dstChainId, lzPayload, _refundAddress, _zroPaymentAddress, _adapterParams, msg.value);

       // emit SendToChain(_dstChainId, _from, _toAddress, amount);
    }

    function sendDeployWithProxy(uint16 _dstChainId, uint256 index, bytes memory data, uint64 _dstGasForCall, address payable _refundAddress, address _zroPaymentAddress, bytes memory _adapterParams) public payable {
        if(chainId == _dstChainId) {
            _deployProxy(_dstChainId, bytes(""), 0, abi.encode(index, data));
            return;
        }
        _checkAdapterParams(_dstChainId, PT_DEPLOY_PROXY, _adapterParams, _dstGasForCall);

        // encode the msg.sender into the payload instead of _from
        bytes memory lzPayload = abi.encode(PT_DEPLOY_PROXY, abi.encode(index, data));
        _lzSend(_dstChainId, lzPayload, _refundAddress, _zroPaymentAddress, _adapterParams, msg.value);

       // emit SendToChain(_dstChainId, _from, _toAddress, amount);
    }

    function sendDirectCall(uint16 _dstChainId, address to, bytes memory data, uint64 _dstGasForCall, address payable _refundAddress, address _zroPaymentAddress, bytes memory _adapterParams) public payable {
        if(chainId == _dstChainId) {
            _directCall(_dstChainId, bytes(""), 0, abi.encode(to, data));
            return;
        }
        _checkAdapterParams(_dstChainId, PT_DIRECT_CALL, _adapterParams, _dstGasForCall);

        // encode the msg.sender into the payload instead of _from
        bytes memory lzPayload = abi.encode(PT_DIRECT_CALL, abi.encode(to, data));
        _lzSend(_dstChainId, lzPayload, _refundAddress, _zroPaymentAddress, _adapterParams, msg.value);

       // emit SendToChain(_dstChainId, _from, _toAddress, amount);
    }

    function _checkAdapterParams(uint16 _dstChainId, uint16 _pkType, bytes memory _adapterParams, uint _extraGas) internal virtual {
        if (useCustomAdapterParams) {
            _checkGasLimit(_dstChainId, _pkType, _adapterParams, _extraGas);
        } else {
            require(_adapterParams.length == 0, "OFTCore: _adapterParams must be empty.");
        }
    }
}
