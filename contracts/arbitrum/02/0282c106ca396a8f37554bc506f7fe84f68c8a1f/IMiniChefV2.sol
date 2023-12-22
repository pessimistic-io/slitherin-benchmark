// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title IMiniChefV2
/// @author Savvy DeFi
interface IMiniChefV2 {
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }
    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
        uint256 depositIncentives;
    }
    function userInfo(uint256 pid, address user) external returns (UserInfo memory);
    function deposit(uint256 pid, uint256 amount, address to) external;
    function withdraw(uint256 pid, uint256 amount, address to) external;
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;

    function poolInfo(uint256 pid) external view returns (PoolInfo memory);
    function SUSHI() external view returns(address);
    function harvest(uint256 pid, address to) external;
}

