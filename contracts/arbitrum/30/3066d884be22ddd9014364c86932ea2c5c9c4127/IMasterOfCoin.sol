// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IMasterOfCoin {
    function requestRewards() external returns (uint256 rewardsPaid);

    function getPendingRewards(address _stream) external view returns (uint256 pendingRewards);

    function setWithdrawStamp() external;

    function setStaticAmount(bool set) external;
}

