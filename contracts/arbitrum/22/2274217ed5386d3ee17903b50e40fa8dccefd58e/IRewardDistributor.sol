// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

interface IRewardDistributor {
    function getRewardTokens() external view returns (address[] memory);

    function getTokensPerIntervals(address _rewardToken) external view returns (uint256);

    function pendingRewards(address _rewardToken) external view returns (uint256);

    function distribute() external returns (uint256[] memory);

    function setTokensPerInterval(address _rewardToken, uint256 _amounts) external;

    function getRewardTokensLength() external returns (uint256);
}

