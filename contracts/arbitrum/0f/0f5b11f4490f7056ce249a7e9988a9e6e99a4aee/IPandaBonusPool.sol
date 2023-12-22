// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface IPandaBonusPool {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function injectRewards(uint256 amount) external;

    function injectRewardsWithTime(
        uint256 amount,
        uint256 rewardsSeconds
    ) external;
}

