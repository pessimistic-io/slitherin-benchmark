// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEnneadRewarder {
    function getReward(address user) external;
    function balanceOf(address user) external view returns (uint256);
    function claimable(address user, address pool) external view returns (uint256);
}

