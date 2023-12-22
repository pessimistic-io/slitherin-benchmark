// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStakeFor {
    function stakeFor(address staker, address token) external returns (uint256);
}
