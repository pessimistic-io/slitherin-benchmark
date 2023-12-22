// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IHlpRewardHandler {
    // function notifyRewardAmount(uint256 reward) external;

    // function getReward(address account) external;

    function getRumSplit(uint256 _amount) external view returns (uint256, uint256, uint256);

    function claimUSDCRewards(address account) external;

    function getPendingUSDCRewards() external view returns (uint256);

    function setDebtRecordUSDC(address _account) external;

    function compoundRewards() external;
}

