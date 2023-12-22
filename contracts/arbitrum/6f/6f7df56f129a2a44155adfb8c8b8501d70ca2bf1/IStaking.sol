// SPDX-License-Identifier: MIT

pragma solidity =0.8.10;

interface IStaking {
    function initialize() external;

    function deposit(uint amount) external;

    function withdraw() external;

    function claimRewards() external;

    function amountStaked(address user) external view returns (uint);

    function totalDeposited() external view returns (uint);

    function rewardOf(address user) external view returns (uint);

    event Deposit(address indexed user, uint amount);

    event Withdraw(address indexed user, uint amount);

    event Claim(address indexed user, uint amount);

    event StartStaking(uint startTime, uint endTime);
}
