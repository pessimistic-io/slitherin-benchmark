// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IdType.sol";

abstract contract IVRFStorage {
    uint8 public constant BUY_REQUEST = 0;
    uint8 public constant CLAIM_REQUEST = 1;

    struct VRFRequest {
        IdType firstTokenId;
        uint16 count;

        uint8 requestType;
        uint8 rarity;
        uint160 reserved;
    }


    function _vrfCoordinator() internal virtual view returns (address);
    function _keyHash() internal virtual view returns (bytes32);
    function _subscriptionId() internal virtual view returns (uint64);
    function _requestConfirmations() internal virtual view returns (uint16);
    function _callbackGasLimit() internal virtual view returns (uint32);
    function _requestMap(uint requestId) internal virtual view returns (VRFRequest storage);
    function _requestMap(uint requestId, uint8 requestType, IdType id, uint16 count) internal virtual;
    function _delRequest(uint requestId) internal virtual;
}

