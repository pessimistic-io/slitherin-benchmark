// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.0.0)

pragma solidity ^0.8.0;

import {LzApp} from "./LzApp.sol";
import {ExcessivelySafeCall} from "./ExcessivelySafeCall.sol";

/*
 * the default LayerZero messaging behaviour is blocking, i.e. any failed message will block the channel
 * this abstract class try-catch all fail messages and store locally for future retry. hence, non-blocking
 * NOTE: if the srcAddress is not configured properly, it will still block the message pathway from (srcChainId, srcAddress)
 */
abstract contract NonblockingLzApp is LzApp {
  using ExcessivelySafeCall for address;

  constructor(address _endpoint) LzApp(_endpoint) {}

  mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32)))
    private failedMessages;

  event MessageFailed(
    uint16 _srcChainId,
    bytes _srcAddress,
    uint64 _nonce,
    bytes _payload,
    bytes _reason
  );
  event RetryMessageSuccess(
    uint16 _srcChainId,
    bytes _srcAddress,
    uint64 _nonce,
    bytes32 _payloadHash
  );

  // overriding the virtual function in LzReceiver
  function _blockingLzReceive(
    uint16 _srcChainId,
    bytes memory _srcAddress,
    uint64 _nonce,
    bytes memory _payload
  ) internal virtual override {
    (bool success, bytes memory reason) = address(this).excessivelySafeCall(
      gasleft(),
      150,
      abi.encodeWithSelector(
        this.nonblockingLzReceive.selector,
        _srcChainId,
        _srcAddress,
        _nonce,
        _payload
      )
    );
    // try-catch all errors/exceptions
    if (!success) {
      failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
      emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, reason);
    }
  }

  function nonblockingLzReceive(
    uint16 _srcChainId,
    bytes calldata _srcAddress,
    uint64 _nonce,
    bytes calldata _payload
  ) public virtual {
    // only internal transaction
    if (_msgSender() != address(this)) {
      _revert(CallerMustBeLzApp.selector);
    }
    _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
  }

  //@notice override this function
  function _nonblockingLzReceive(
    uint16 _srcChainId,
    bytes memory _srcAddress,
    uint64 _nonce,
    bytes memory _payload
  ) internal virtual;

  function retryMessage(
    uint16 _srcChainId,
    bytes calldata _srcAddress,
    uint64 _nonce,
    bytes calldata _payload
  ) public payable virtual {
    // assert there is message to retry
    bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
    if (payloadHash == bytes32(0)) {
      _revert(NoStoredMessage.selector);
    }
    if (keccak256(_payload) != payloadHash) {
      _revert(InvalidPayload.selector);
    }
    failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
    // execute the message. revert if it fails again
    _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
  }
}

