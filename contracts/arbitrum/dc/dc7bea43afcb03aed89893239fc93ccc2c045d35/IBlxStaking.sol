// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBlxStaking {
    function getTotalStake() external view returns (uint256);
    function notifyStakingLossAmount(uint amount) external;
    function notifyRewardAmount(uint amount) external;
    function deposit(uint blxAmount) external returns (uint256);
    function withdraw(uint blxAmount) external returns (uint256);
    function lock(uint duration) external;
    function claimReward() external;
    function stakerCount() external returns (uint256);
}

