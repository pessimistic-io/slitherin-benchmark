// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IHopRewardPool {
    function exit() external;

    function getReward() external;

    function earned() external view returns (uint256);

    function stake(uint256 currencyAmount) external;

    function withdraw(uint256 currencyAmount) external;

    function balanceOf(address account) external view returns (uint256);
}

