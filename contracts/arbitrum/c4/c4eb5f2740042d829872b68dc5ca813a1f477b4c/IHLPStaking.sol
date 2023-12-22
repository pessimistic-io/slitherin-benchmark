// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IHLPStaking {
    function withdraw(uint256 amount) external;

    function deposit(address to, uint256 amount) external;

    function userTokenAmount(address user) external view returns (uint256);
}

