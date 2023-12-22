// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

interface IRamsesGaugeV2 {
    function positionInfo(uint256) external view returns (uint128, uint128, uint256);
    function earned(address, uint256) external view returns (uint256);
}

