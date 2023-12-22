// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IPositionRouterCallbackReceiver {
    // function isContract() external view returns (bool);

    function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external;
}

