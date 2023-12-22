// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IQueueContract {
    function transferToStrategy(uint256 amount) external;

    function transferToQueue(address caller, uint256 amount) external;

    function balance(address sender) external view returns (uint256);
}

