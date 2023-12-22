// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBoosterOracle {
    // Must 8 dec, same as chainlink decimals.
    function getPrice(address token) external view returns (uint256);
}

