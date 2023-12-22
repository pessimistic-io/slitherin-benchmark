//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface ICallbackForwarder {
    function gmxPositionCallback(
        bytes32 positionKey,
        bool isExecuted,
        bool
    ) external;

    function createIncreaseOrder(uint256 _positionId) external;
}

