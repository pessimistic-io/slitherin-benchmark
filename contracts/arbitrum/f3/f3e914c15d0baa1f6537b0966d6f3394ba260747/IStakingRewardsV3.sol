// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IStakingRewardsV3 {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function earned(address account) external view returns (uint256 tokensEarned);

    function stake(uint256 amount) external;

    function unstake(uint256 amount) external;

    function claim() external;

    function exit() external;

    function addToContractWhitelist(address _contract) external;
}

