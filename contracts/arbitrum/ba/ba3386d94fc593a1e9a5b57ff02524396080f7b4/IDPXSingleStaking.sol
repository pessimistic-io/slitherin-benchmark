// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.2;

interface IDPXSingleStaking {
    function balanceOf(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward(uint256 rewardsTokenID) external;

    function compound() external;

    function exit() external;
}

