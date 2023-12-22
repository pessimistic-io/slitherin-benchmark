// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardRouterV2 {
    function feeXlpTracker() external view returns (address);

    function stakedXlpTracker() external view returns (address);
}

