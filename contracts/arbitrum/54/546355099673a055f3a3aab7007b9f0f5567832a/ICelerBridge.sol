// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICelerBridge {
    function send(
        address _receiver,
        address _token,
        uint256 _amount,
        uint64 _dstChainId,
        uint64 _nonce,
        uint32 _maxSlippage
    ) external;
}

