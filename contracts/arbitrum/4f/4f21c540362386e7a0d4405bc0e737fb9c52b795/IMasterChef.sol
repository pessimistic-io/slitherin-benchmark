// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMasterChef {
    function unstakeAndLiquidate(uint256 pid, address user, uint256 amount) external;
}

