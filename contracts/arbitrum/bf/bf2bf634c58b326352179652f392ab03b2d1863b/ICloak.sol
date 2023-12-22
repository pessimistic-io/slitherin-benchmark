// SPDX-License-Identifier: UNLICENSED
// Author: @stevieraykatz
// https://github.com/coinlander/Coinlander

pragma solidity ^0.8.10;

interface ICloak {
    function getDethscales(
        uint16 minDethscales,
        uint16 maxDethscales,
        uint16 seed,
        uint16 salt
    ) external pure returns (uint16);

    function getFullCloak(
        uint16 minNoiseBits,
        uint16 maxNoiseBits,
        uint16 _dethscales
    ) external pure returns (uint32[32] memory);
}
