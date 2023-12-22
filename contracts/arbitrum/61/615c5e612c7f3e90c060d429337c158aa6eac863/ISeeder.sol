// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18 <0.9.0;

interface ISeeder {
    function generateSeed(uint256 salt) external view returns (uint256 seed);
}

