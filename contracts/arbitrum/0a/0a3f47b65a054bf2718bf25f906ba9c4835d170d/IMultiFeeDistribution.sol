// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

interface IMultiFeeDistribution {
    function addReward(address rewardsToken) external;

    function mint(address user, uint256 amount, bool withPenalty) external;
}

