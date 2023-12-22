// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IExternalBribeFactory {
    function createExternalBribe(address voter, address[] memory allowedRewards) external returns (address);
}

