// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IArbRewardDistributor {
    function rewardToken() external view returns (address);

    function updateRewards(address account) external;

    function rewardRate() external view returns (uint256);
}

