// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStakingRewards {
    // Views
    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256, uint256);

    function earned(address account) external view returns (uint256, uint256);

    function getRewardForDuration() external view returns (uint256, uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    // Mutative
    function stake(uint256 amount) external payable;

    function withdraw(uint256 amount) external;

    function getReward(uint256 rewardsTokenID) external;

    function exit() external;

    function addToContractWhitelist(address _contract) external;
}

