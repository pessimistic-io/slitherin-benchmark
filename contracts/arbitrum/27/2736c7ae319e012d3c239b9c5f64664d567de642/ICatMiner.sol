//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICatMiner {
    event Deposited(address account, uint value, address refAccount);
    event Compounded(address account, uint value);
    event RewardClaimed(address account, uint value);

    function deposit(address refAddress) external payable;
    function claimReward() external;
    function compoundReward() external;
}
