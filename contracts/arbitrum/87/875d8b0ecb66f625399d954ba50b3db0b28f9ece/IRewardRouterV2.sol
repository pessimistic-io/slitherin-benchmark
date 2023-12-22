// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewardRouterV2 {
    function feeGlpTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);

    function compound() external;
    function claimFees() external;
}

