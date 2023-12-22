// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Metadata.sol";

interface IStakingInterface {
    function userInfo(address _user) external view returns (uint256 amount, uint256 rewardDebt);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function emergencyWithdraw() external;

    function claimReward() external;

    function pendingReward(address _user) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
