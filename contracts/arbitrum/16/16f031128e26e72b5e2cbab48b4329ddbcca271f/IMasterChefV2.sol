// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";

library MasterChefStructs {
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }
}

library RewarderStructs {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    struct PoolInfo {
        uint128 accToken1PerShare;
        uint64 lastRewardTime;
    }
}

interface IRewarder {
    function userInfo(uint256 _pid, address _user) external view returns (RewarderStructs.UserInfo memory);

    function poolInfo(uint256 _pid) external view returns (RewarderStructs.PoolInfo memory);

    function onSushiReward(uint256 pid, address user, address recipient, uint256 sushiAmount, uint256 newLpAmount)
        external;
    function pendingTokens(uint256 pid, address user, uint256 sushiAmount)
        external
        view
        returns (IERC20[] memory, uint256[] memory);

    function rewardPerSecond() external returns (uint256);
}

interface IMasterChefV2 {
    function userInfo(uint256 _pid, address _user) external view returns (MasterChefStructs.UserInfo memory);

    function poolInfo(uint256 _pid) external view returns (MasterChefStructs.PoolInfo memory);

    function pendingSushi(uint256 _pid, address _user) external view returns (uint256 pending);

    function deposit(uint256 pid, uint256 amount, address to) external;

    function withdraw(uint256 pid, uint256 amount, address to) external;

    function harvest(uint256 pid, address to) external;

    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;

    function rewarder(uint256 _pid) external view returns (IRewarder);

    function sushiPerSecond() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);
}

