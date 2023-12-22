// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IStateReceiver {
    function onStateReceive(uint256 id, bytes calldata data) external;
}

