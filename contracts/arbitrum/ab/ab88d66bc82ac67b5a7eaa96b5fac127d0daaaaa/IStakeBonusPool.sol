// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IStakeBonusPool {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function addBonus(uint256 amount) external;
    function addBonusWithTime(uint256 amount, uint256 rewardsSeconds) external;
}

