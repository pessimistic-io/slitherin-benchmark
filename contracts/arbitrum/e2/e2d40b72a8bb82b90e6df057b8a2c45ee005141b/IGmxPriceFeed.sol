// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IGmxVaultPriceFeed {
    function secondaryPriceFeed() external view returns (address);
}

