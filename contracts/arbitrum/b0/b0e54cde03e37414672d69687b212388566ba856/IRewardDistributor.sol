// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRewardDistributor {
    function pendingRewards() external view returns (uint256);

    function setTokensPerInterval(uint256 _amount) external;
}

