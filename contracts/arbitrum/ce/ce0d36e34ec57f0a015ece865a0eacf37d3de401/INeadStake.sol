// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INeadStake {
    function deposit(uint amount) external;
    function withdraw(uint amount) external;
    function getReward() external;
    function balanceOf(address account) external view returns (uint);
    function rewardsList() external view returns (address[] memory rewards);
}
