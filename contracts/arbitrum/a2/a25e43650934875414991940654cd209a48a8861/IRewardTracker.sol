// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

interface IRewardTracker {
    function deposit(uint256 amount, uint256 _lockTime) external;
    function withdraw(uint256 amount, uint256 _lockTime) external;
    function claim(uint256 _lockTime) external;
    function claimable(address account) external view returns (uint256);
}

