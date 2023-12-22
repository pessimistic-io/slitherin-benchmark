// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IOracleConnector {
    function name() external view returns (string memory);
    function decimals() external view returns (uint256);
    function paused() external view returns (bool);
    function validateTimestamp(uint256) external view returns (bool);
    function getRoundData(
        uint256 roundId_
    )
        external
        view
        returns (uint256 roundId, uint256 answer, uint256 startedAt, uint256 updatedAt, uint256 answeredInRound);
    function latestRound() external view returns (uint256);
    function latestRoundData()
        external
        view
        returns (uint256 roundId, uint256 answer, uint256 startedAt, uint256 updatedAt, uint256 answeredInRound);
}

