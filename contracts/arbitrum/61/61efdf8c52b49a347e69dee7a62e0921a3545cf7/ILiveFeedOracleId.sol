// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/// @title Opium.Interface.ILiveFeedOracleId is an interface that every LiveFeed oracleId should implement
interface ILiveFeedOracleId {
    /// @notice 
    /// @param timestamp - Timestamp at which data are needed
    function _callback(uint256 timestamp) external;

    /// @notice Returns current value of the oracle if possible, or last known value
    function getResult() external view returns (uint256 result);

    // Event with oracleId metadata JSON string (for Opium derivative explorer)
    event LogMetadataSet(string metadata);
}

