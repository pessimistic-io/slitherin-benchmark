// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBaseRewardPoolV3 {
    function allEarned(address _account) external view returns (uint256[] memory pendingBonusRewards);
}
