//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStakingStrategy {
    function stake(uint256) external returns (uint256[] memory);

    function unstake() external returns (uint256[] memory);

    function getRewardTokens() external view returns (address[] memory);
}

