// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {VanillaOptionPool} from "./VanillaOptionPool.sol";

interface IV3PoolOptions {
    function pricesAtExpiries(uint256 expiry) external returns (uint256);

    function getAvailableStrikes(
        uint256 expiry,
        bool isCall
    ) external view returns (uint256[] memory strikes);

    function poolsBalances(
        bytes32 vaillaOptionPoolHash
    ) external view returns (uint256, uint256);
}

