// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface ILBPair {
    function getOracleSampleAt(
        uint40 lookupTimestamp
    )
        external
        view
        returns (
            uint64 cumulativeId,
            uint64 cumulativeVolatility,
            uint64 cumulativeBinCrossed
        );

    function getPriceFromId(uint24 id) external view returns (uint256 price);
}

