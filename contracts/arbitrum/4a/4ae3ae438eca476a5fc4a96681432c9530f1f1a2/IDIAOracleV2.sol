// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDIAOracleV2 {
    function getValue(
        string memory key
    ) external view returns (uint128, uint128);
}

