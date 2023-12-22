// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IRewardDistributor {
    function receiveReward(address _asset, uint256 _amount) external;
}

