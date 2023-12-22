// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStakingRewards {

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    // Mutative

    function _stake(address account, uint256 amount) external;

    function _withdraw(address account, uint256 amount) external;

    function _getReward(address account) external;
}

