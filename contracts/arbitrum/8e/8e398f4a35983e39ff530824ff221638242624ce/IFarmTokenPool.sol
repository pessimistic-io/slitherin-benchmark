// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFarmTokenPool {
    struct User {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct Pool {
        bool isActive;
        uint256 creationTS;
        uint256 accRewardPerShare;
        uint256 totalStaked;
    }

    // function pool(uint256 trancheId) external view returns (Pool memory);

    // function users(uint256 trancheId, address user) external view returns (User memory);

    function sendRewards(address rewardToken, uint256 trancheId, uint256 _amount) external;

    function unstake(address rewardToken, uint256 trancheId, address account, uint256 _amount) external;

    function stake(address rewardToken, uint256 trancheId, address account, uint256 _amount) external;

    function changeRewardTokens(address[] memory toAdd, address[] memory toPause, address[] memory newTokens) external;
}

