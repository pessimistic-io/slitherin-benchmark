// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IMarketUtils.sol";

interface IOracle {
    function getPrimaryPrice(address token) external view returns (Price.Props memory);

    function getStablePrice(address dataStore, address token) external view returns (uint256);
}

