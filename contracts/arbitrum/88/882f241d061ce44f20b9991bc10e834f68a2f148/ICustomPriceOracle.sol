// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ICustomPriceOracle {
    function getPriceInUSD() external view returns (uint256);
}

