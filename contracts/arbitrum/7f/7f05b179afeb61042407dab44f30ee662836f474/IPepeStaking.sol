//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPepeStaking {
    function stake(uint256 amount) external;

    function unStake(uint256 amount) external;

    function exit() external;

    function updateRewards() external;

    function claimRewards() external;

    function pendingRewards(address user) external view returns (uint256);

    function getUserStake(address user) external view returns (uint256);

    function setFeeDistributor(address feeDistributor) external;
}

