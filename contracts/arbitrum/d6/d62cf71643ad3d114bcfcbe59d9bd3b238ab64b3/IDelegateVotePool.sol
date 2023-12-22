// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IDelegateVotePool {
    function getReward(address _for)
        external
        returns (
            address[] memory rewardTokensList,
            uint256[] memory earnedRewards
        );
}

