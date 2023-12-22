// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * Interface for a data provider adapters
 */
interface IDataProvider {
    function quoteSOLToETH(
        uint256 solAmount
    ) external view returns (uint256 ethAmount);

    function quoteSOLToToken(
        address pairToken,
        uint256 solAmount
    ) external view returns (uint256 tokenAmount);

    function quoteETHToToken(
        address pairToken,
        uint256 ethAmount
    ) external view returns (uint256 tokenAmount);
}

