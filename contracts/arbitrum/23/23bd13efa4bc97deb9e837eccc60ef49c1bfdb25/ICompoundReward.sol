// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICompoundReward {
    function claim(address comet, address src, bool shouldAccrue) external;
    function getRewardOwed(address comet, address account) external;
}

