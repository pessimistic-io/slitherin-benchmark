// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILPStaking {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    function stargate() external view returns (address);
    function pendingStargate(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 pid, address _user) external view returns (UserInfo memory);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
}
