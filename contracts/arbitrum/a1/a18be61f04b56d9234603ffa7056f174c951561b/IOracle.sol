// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.6;

/// @title IOracle
/// @notice Read price of various token
interface IOracle {
    function getPrice(address token) external view returns (uint256);
    function getPrice(address token, bool max) external view returns (uint256);
    function getMultiplePrices(address[] calldata tokens, bool max) external view returns (uint256[] memory);
    function getMultipleChainlinkPrices(address[] calldata tokens) external view returns (uint256[] memory);
}

