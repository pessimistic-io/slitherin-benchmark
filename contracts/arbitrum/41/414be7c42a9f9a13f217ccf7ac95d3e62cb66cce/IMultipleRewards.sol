// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IBoringERC20.sol";

interface IMultipleRewards {
    function onZyberReward(
        uint256 pid,
        address user,
        uint256 newLpAmount
    ) external;

    function pendingTokens(
        uint256 pid,
        address user
    ) external view returns (uint256 pending);

    function rewardToken() external view returns (IBoringERC20);

    function poolRewardsPerSec(uint256 pid) external view returns (uint256);
}

