//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

interface IVolatilityOracle {
    function getVolatility(uint256) external view returns (uint256);
}

