// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.0.0)

pragma solidity ^0.8.0;

import {IONFT721Core} from "./IONFT721Core.sol";
import {NonblockingLzApp} from "./NonblockingLzApp.sol";

abstract contract ONFT721Core is NonblockingLzApp, IONFT721Core {
  uint256 private constant NO_EXTRA_GAS = 0;
  uint16 private constant FUNCTION_TYPE_SEND = 1;
  bool private useCustomAdapterParams;

  constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {}

  function estimateSendFee(
    uint16 _dstChainId,
    bytes memory _toAddress,
    uint256 _tokenId,
    bool _useZro,
    bytes memory _adapterParams
  ) public view virtual override returns (uint256 nativeFee, uint256 zroFee) {
    // mock the payload for send()
    bytes memory payload = abi.encode(_toAddress, _tokenId);
    return
      lzEndpoint.estimateFees(
        _dstChainId,
        address(this),
        payload,
        _useZro,
        _adapterParams
      );
  }

  function sendFrom(
    address _from,
    uint16 _dstChainId,
    bytes memory _toAddress,
    uint256 _tokenId,
    address payable _refundAddress,
    address _zroPaymentAddress,
    bytes memory _adapterParams
  ) public payable virtual override {
    _send(
      _from,
      _dstChainId,
      _toAddress,
      _tokenId,
      _refundAddress,
      _zroPaymentAddress,
      _adapterParams
    );
  }

  function _send(
    address _from,
    uint16 _dstChainId,
    bytes memory _toAddress,
    uint256 _tokenId,
    address payable _refundAddress,
    address _zroPaymentAddress,
    bytes memory _adapterParams
  ) internal virtual {
    _debitFrom(_from, _dstChainId, _toAddress, _tokenId);

    bytes memory payload = abi.encode(_toAddress, _tokenId);

    if (useCustomAdapterParams) {
      _checkGasLimit(
        _dstChainId,
        FUNCTION_TYPE_SEND,
        _adapterParams,
        NO_EXTRA_GAS
      );
    } else {
      if (_adapterParams.length != 0) {
        _revert(AdapterParamsMustBeEmpty.selector);
      }
    }
    _lzSend(
      _dstChainId,
      payload,
      _refundAddress,
      _zroPaymentAddress,
      _adapterParams,
      msg.value
    );

    emit SendToChain(_dstChainId, _from, _toAddress, _tokenId);
  }

  function _nonblockingLzReceive(
    uint16 _srcChainId,
    bytes memory _srcAddress,
    uint64 /*_nonce*/,
    bytes memory _payload
  ) internal virtual override {
    (bytes memory toAddressBytes, uint256 tokenId) = abi.decode(
      _payload,
      (bytes, uint256)
    );
    address toAddress;
    assembly {
      toAddress := mload(add(toAddressBytes, 20))
    }

    _creditTo(_srcChainId, toAddress, tokenId);

    emit ReceiveFromChain(_srcChainId, _srcAddress, toAddress, tokenId);
  }

  function setUseCustomAdapterParams(
    bool _useCustomAdapterParams
  ) external onlyOwner {
    useCustomAdapterParams = _useCustomAdapterParams;
    emit SetUseCustomAdapterParams(_useCustomAdapterParams);
  }

  function _debitFrom(
    address _from,
    uint16 _dstChainId,
    bytes memory _toAddress,
    uint256 _tokenId
  ) internal virtual;

  function _creditTo(
    uint16 _srcChainId,
    address _toAddress,
    uint256 _tokenId
  ) internal virtual;
}

