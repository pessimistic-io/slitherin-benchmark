// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISmartChefInitializable {
    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt;
    }
    function userInfo(address _user) external view returns (UserInfo memory);
    function pendingReward(address _user) external view returns (uint256);
    function rewardToken() external view returns (address);
    function hasUserLimit() external view returns (bool);
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
}

