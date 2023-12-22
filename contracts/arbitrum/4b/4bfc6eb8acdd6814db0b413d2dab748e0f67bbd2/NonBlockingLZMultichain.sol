// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./NonblockingLzApp.sol";

abstract contract NonBlockingLZMultichain is NonblockingLzApp {
    uint16[] public activeChainIds;
    // packet type
    uint8 public constant PT_CONFIG = 69;

    event SendConfig(uint16 dstChainId, bytes data);

    modifier onlyOwner() override {
        require(msg.sender == owner || msg.sender == address(this), "Ownable: caller is not the owner");
        _;
    }

    constructor(address _endpoint) NonblockingLzApp(_endpoint) {}

    function sendConfig(uint16 _dstChainId, bytes calldata data, uint64 gasForCall, bytes memory _adapterParams) public virtual payable onlyOwner {
        bytes memory payload = abi.encode(PT_CONFIG, abi.encode(data, gasForCall));

        _checkGasLimit(_dstChainId, PT_CONFIG, _adapterParams, 0);
        _lzSend(_dstChainId, payload, payable(msg.sender), address(0), _adapterParams, msg.value);
        emit SendConfig(_dstChainId, data);
    }

    function sendConfigToAll(bytes calldata data, uint64 gasForCall, bytes memory _adapterParams) public virtual payable onlyOwner {
        (bool success, bytes memory result) = address(this).call(data);
        require(success, "Config failed");
        for (uint i; i < activeChainIds.length; i++) {
            sendConfig(activeChainIds[i], data, gasForCall, _adapterParams);
        }
    }

    function _setTrustedRemote(uint16 _remoteChainId, bytes memory _path) internal {
        int index = -1;
        for (uint i; i < activeChainIds.length; i++) {
            if (activeChainIds[i] == _remoteChainId) {
                index = int(i);
                break;
            }
        }
        if(_path.length != 0) {
            if (index == -1) {
                activeChainIds.push(_remoteChainId);
            } else {
                activeChainIds[uint(index)] = _remoteChainId;
            }
        } else {
            if (index != -1) {
                activeChainIds[uint(index)] = activeChainIds[activeChainIds.length - 1];
                activeChainIds.pop();
            }
        }
        trustedRemoteLookup[_remoteChainId] = _path;
        emit SetTrustedRemote(_remoteChainId, _path);
    }

    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external override onlyOwner {
        _setTrustedRemote(_remoteChainId, _path);
    }

    function setTrustedRemoteAddress(uint16 _remoteChainId, bytes calldata _remoteAddress) external override onlyOwner {
        bytes memory _path = abi.encodePacked(_remoteAddress, address(this));
         _setTrustedRemote(_remoteChainId, _path);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 nonce, /*_nonce*/
        bytes memory _payload,
        bool retry
    ) internal override {
        (uint8 payloadType, bytes memory payload) = abi.decode(_payload, (uint8, bytes));
        
        if (payloadType == PT_CONFIG) {
            // call, using low level call to not revert on EOA
            uint64 gasForCall;
            (payload, gasForCall) = abi.decode(payload, (bytes, uint64));
            uint gas = retry ? gasleft() : gasForCall;
            (bool success, bytes memory result) = address(this).call{gas: gas}(payload);
            
            if (!success) { // If call reverts
                // If there is return data, the call reverted without a reason or a custom error.
                if (result.length == 0) revert();
                assembly {
                    // We use Yul's revert() to bubble up errors from the target contract.
                    revert(add(32, result), mload(result))
                }
            }
        } else {
            _nonblockingLzReceiveAfterConfig(_srcChainId, _srcAddress, nonce, _payload, payloadType, retry);
        }
    }

    function _nonblockingLzReceiveAfterConfig(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 nonce, /*_nonce*/
        bytes memory _payload,
        uint8 payloadType,
        bool retry
    ) internal virtual;


    function nonblockingLzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public virtual override {
        // only internal transaction
        require(msg.sender == address(this), "NonblockingLzApp: caller must be LzApp");
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload, false);
    }

}
