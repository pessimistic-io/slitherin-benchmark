// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.5.0;

interface IVaultStrategy {
    function getBalance(address strategist) external view returns (uint256);
}
