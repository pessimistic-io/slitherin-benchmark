// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IRewardTracker {
    function balanceOf(address _account) external view returns (uint256);
}
