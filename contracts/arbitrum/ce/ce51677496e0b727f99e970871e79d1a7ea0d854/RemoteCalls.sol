// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

abstract contract RemoteCalls {
    enum RemoteCallsType {
        LZ
    }

    event RemoteCall(bytes calldata_);

    error RemoteCallFailed();

    modifier remoteFn() {
        if (msg.sender != address(this)) revert RemoteCallFailed();
        _;
    }

    function remoteCallType() external pure virtual returns (RemoteCallsType);

    function _startRemoteCall(
        bytes memory calldata_,
        bytes calldata bridgeParams
    ) internal {
        _remoteCall(calldata_, bridgeParams);
    }

    function _finishRemoteCall(bytes memory calldata_) internal {
        (bool success, ) = address(this).call(calldata_);
        if (!success) revert RemoteCallFailed();
    }

    function _remoteCall(
        bytes memory calldata_,
        bytes calldata bridgeParams
    ) internal virtual;
}

