// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRamsesV2Pool {
    function liquidity() external view returns (uint128);
    function boostedLiquidity() external view returns (uint128);
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}



