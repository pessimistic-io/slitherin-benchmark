// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

abstract contract RemoteCalls {
    event RemoteCall(bytes calldata_);

    modifier remoteFn() {
        require(msg.sender == address(this));
        _;
    }

    function _startRemoteCall(
        bytes memory calldata_,
        bytes calldata bridgeParams
    ) internal {
        _remoteCall(calldata_, bridgeParams);
        emit RemoteCall(calldata_);
    }

    function _finishRemoteCall(bytes memory calldata_) internal {
        address(this).call(calldata_);
    }

    function _remoteCall(
        bytes memory calldata_,
        bytes calldata bridgeParams
    ) internal virtual;
}

