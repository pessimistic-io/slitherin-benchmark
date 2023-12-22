// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IOracleAdapter {
    function getSinglePrice(
        address asset,
        uint64 timestamp
    ) external view returns (uint256);

    function getPrice(
        address baseAsset,
        address quoteAsset,
        uint64 timestamp
    ) external view returns (uint256);
}

