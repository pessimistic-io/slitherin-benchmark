// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOpManager {
    function isRunning(address _op) external view returns (bool);
}

