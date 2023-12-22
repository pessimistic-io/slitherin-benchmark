// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IBalancerGauge {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function reward_tokens(uint256) external view returns (address);
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function claim_rewards() external;
}

interface IBalancerGaugeFactory {
    function getPoolGauge(address) external view returns (address);
}

