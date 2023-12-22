// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewardRouterV2 {
    function feeUlpTracker() external view returns (address);
    function stakedUlpTracker() external view returns (address);
}

