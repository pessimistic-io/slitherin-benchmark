// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

interface IRamsesClFactory {
    function getPool(address, address, uint24) external view returns (address);
}

