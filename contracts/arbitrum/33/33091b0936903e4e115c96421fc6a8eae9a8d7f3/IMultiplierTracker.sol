// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IMultiplierTracker {
    function getVestingMultiplier() external view returns (uint256);
    function getStakingMultiplier() external view returns (uint256);
}

