// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @notice TraderJoe liquidity book pair interface
interface IJoeLBPair {
    /**
     * @notice Returns the cumulative values of the Liquidity Book Pair at a given timestamp
     * @dev The cumulative values are the cumulative id, the cumulative volatility and the cumulative bin crossed.
     * @param lookupTimestamp The timestamp at which to look up the cumulative values
     * @return cumulativeId The cumulative id of the Liquidity Book Pair at the given timestamp
     * @return cumulativeVolatility The cumulative volatility of the Liquidity Book Pair at the given timestamp
     * @return cumulativeBinCrossed The cumulative bin crossed of the Liquidity Book Pair at the given timestamp
     */
    function getOracleSampleAt(uint40 lookupTimestamp)
        external
        view
        returns (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed);

    /**
     * @notice Returns the oracle parameters of the Liquidity Book Pair
     * @return sampleLifetime The sample lifetime for the oracle
     * @return size The size of the oracle
     * @return activeSize The active size of the oracle
     * @return lastUpdated The last updated timestamp of the oracle
     * @return firstTimestamp The first timestamp of the oracle, i.e. the timestamp of the oldest sample
     */
    function getOracleParameters()
        external
        view
        returns (uint8 sampleLifetime, uint16 size, uint16 activeSize, uint40 lastUpdated, uint40 firstTimestamp);

    /**
     * @notice Returns the price corresponding to the given id, as a 128.128-binary fixed-point number
     * @dev This is the trusted source of price information, always trust this rather than getIdFromPrice
     * @param id The id of the bin
     * @return price The price corresponding to this id
     */
    function getPriceFromId(uint24 id) external view returns (uint256 price);
}

