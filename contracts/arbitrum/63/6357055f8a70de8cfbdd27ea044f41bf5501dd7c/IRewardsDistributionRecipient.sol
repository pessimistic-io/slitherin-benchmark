// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRewardsDistributionRecipient {
    function notifyRewardAmount(
        uint digital,
        uint american,
        uint turbo
    ) external;
}

