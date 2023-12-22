// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {NonblockingLzApp, ExcessivelySafeCall, BytesLib} from "./NonblockingLzApp.sol";
import {console2} from "./Test.sol";

abstract contract Base is NonblockingLzApp {
    using BytesLib for bytes;
    uint256 public constant NO_EXTRA_GAS = 0;
    // packet types
    uint16 public constant PT_SEND = 0;
    uint16 public constant PT_REBASE = 1;
    uint16 public constant PT_MERKLE = 2;

    bool public useCustomAdapterParams;

    // Store all remote chains.
    uint16[] public remoteChains;

    event SetUseCustomAdapterParams(bool _useCustomAdapterParams);

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {}

    function setUseCustomAdapterParams(bool _useCustomAdapterParams) public virtual onlyOwner {
        useCustomAdapterParams = _useCustomAdapterParams;
        emit SetUseCustomAdapterParams(_useCustomAdapterParams);
    }

    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external override virtual onlyOwner {
        _setRemoteChain(_remoteChainId, _path);
        trustedRemoteLookup[_remoteChainId] = _path;
        emit SetTrustedRemote(_remoteChainId, _path);
    }

    function setTrustedRemoteAddress(uint16 _remoteChainId, bytes calldata _remoteAddress)
        external
        override
        virtual
        onlyOwner
    {
        bytes memory _path = abi.encodePacked(_remoteAddress, address(this));
        _setRemoteChain(_remoteChainId, _path);
        trustedRemoteLookup[_remoteChainId] = _path;
        emit SetTrustedRemoteAddress(_remoteChainId, _remoteAddress);
    }

    function _receive(bytes memory _payload) internal virtual;
    function _setRebase(bytes memory _payload) internal virtual;
    function _setMerkle(bytes memory payload) internal virtual;

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal override {
        uint16 packetType;
        assembly {
            packetType := mload(add(_payload, 32))
        }

        if (packetType == PT_SEND) {
            _receive(_payload);
        } else if (packetType == PT_REBASE) {
            _setRebase(_payload);
        } else if (packetType == PT_MERKLE) {
            _setMerkle(_payload);
        } else {
            revert("Unknown packet type.");
        }
    }

    // Keep track of trusted remotes so we can iterate over them in _propagate().
    function _setRemoteChain(uint16 _chainId, bytes memory _path) internal {
        bytes memory current = trustedRemoteLookup[_chainId];
        bool alreadySet = current.length != 0 && current.toAddress(0) != address(0);
        bool addingNew = _path.length != 0 && _path.toAddress(0) != address(0);
        if (!alreadySet && addingNew) {
            // In this case, we are adding a new remote.
            remoteChains.push(_chainId);
        } else if (alreadySet && !addingNew) {
            // In this case, we are removing a remote.
            for (uint256 i = 0; i < remoteChains.length; i++) {
                if (remoteChains[i] == _chainId) {
                    remoteChains[i] = remoteChains[remoteChains.length - 1];
                    remoteChains.pop();
                    break;
                }
            }
        }
    }

    function _propagate(
        bytes memory payload,
        address payable refundAddress,
        address zroPaymentAddress,
        uint256[] calldata nativeFees
    ) internal {
        require(nativeFees.length == remoteChains.length, "Invalid fee array.");
        for (uint256 i = 0; i < remoteChains.length; i++) {
            _lzSend(remoteChains[i], payload, refundAddress, zroPaymentAddress, bytes(""), nativeFees[i]);
        }
    }

    function _estimatePropageteFees(bytes memory payload, bool useZro, bytes calldata adapterParams)
        internal
        view
        returns (uint256[] memory nativeFees, uint256[] memory zroFees, uint256 totalNativeFees, uint256 totalZroFees)
    {
        nativeFees = new uint[](remoteChains.length);
        zroFees = new uint[](remoteChains.length);
        for (uint256 i = 0; i < remoteChains.length; i++) {
            (nativeFees[i], zroFees[i]) =
                lzEndpoint.estimateFees(remoteChains[i], address(this), payload, useZro, adapterParams);
            totalNativeFees += nativeFees[i];
            totalZroFees += zroFees[i];
        }
    }

    function _checkAdapterParams(uint16 _dstChainId, uint16 _pkType, bytes memory _adapterParams, uint256 _extraGas)
        internal
        virtual
    {
        if (useCustomAdapterParams) {
            _checkGasLimit(_dstChainId, _pkType, _adapterParams, _extraGas);
        } else {
            require(_adapterParams.length == 0, "OFTCore: _adapterParams must be empty.");
        }
    }
}

