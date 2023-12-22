// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INeadStake {
    function notifyRewardAmount(address token, uint amount) external;
    function deposit(address account, uint amount) external;
    function withdraw(address account, uint amount) external;
    function getReward() external;
}
