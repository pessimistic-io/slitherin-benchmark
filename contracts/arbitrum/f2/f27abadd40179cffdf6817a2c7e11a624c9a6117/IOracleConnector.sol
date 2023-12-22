// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IOracleConnector {
    function name() external view returns (string memory);
    function decimals() external view returns (uint256);
    function validateTimestamp(uint256) external view returns (bool);
    function getPrice() external view returns (uint256);
}

