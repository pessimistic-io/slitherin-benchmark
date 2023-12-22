// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.17;

interface ICallProxy {
    function proxyCall(
        address token,
        uint256 amount,
        address receiver,
        bytes memory callData
    ) external returns (bool);
}

