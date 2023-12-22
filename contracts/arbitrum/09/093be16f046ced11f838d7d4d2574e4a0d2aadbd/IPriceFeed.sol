// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

/// @title IPriceFeed
/// @dev Interface for a price feed
interface IPriceFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}
