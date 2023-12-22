// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRamsesClFactory {
    function getPool(address, address, uint24) external view returns (address);
}

