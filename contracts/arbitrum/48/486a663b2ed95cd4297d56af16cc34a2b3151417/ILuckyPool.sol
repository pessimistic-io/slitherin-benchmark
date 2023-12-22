// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILuckyPool {
    function trade(address user, uint256 usd) external;

    function claimReward() external;

    function inProgress() external view returns (bool);
}

