// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

interface IStakeReward {
    function stake(uint256 _amount) external;   
    function withdraw(uint256 _amount) external; // only withdraw; do not claim 
    function claimAll(address _address) external; 
    function exit(address _address) external; // claim and withdraw
    function stakedTokensOf(address _address) external view returns (uint256);
}
