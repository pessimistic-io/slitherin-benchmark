// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @custom:version 5
 */
interface IChainlinkFeed {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

