// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";

interface IRewarder {
    function onSushiReward(uint256 pid, address user, address recipient, uint256 sushiAmount, uint256 newLpAmount)
        external;
    function pendingTokens(uint256 pid, address user, uint256 sushiAmount)
        external
        view
        returns (IERC20[] memory, uint256[] memory);
}

library UserStruct {
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }
}

interface IMasterChefV2 {
    function userInfo(uint256 _pid, address _user) external view returns (UserStruct.UserInfo memory);

    function pendingSushi(uint256 _pid, address _user) external view returns (uint256 pending);

    function deposit(uint256 pid, uint256 amount, address to) external;

    function withdraw(uint256 pid, uint256 amount, address to) external;

    function harvest(uint256 pid, address to) external;

    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;

    function rewarder(uint256 _pid) external view returns (IRewarder);
}

