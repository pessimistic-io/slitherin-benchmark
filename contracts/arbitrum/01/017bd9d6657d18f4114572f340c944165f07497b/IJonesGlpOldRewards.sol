// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IJonesGlpOldRewards {
    function balanceOf(address _user) external returns (uint256);
    function getReward(address _user) external returns (uint256);
    function withdraw(address _user, uint256 _amount) external;
}

