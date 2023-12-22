// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IChainlinkDataFeedFactory {
    function createChainlinkDataFeed(address owner, address authorized, string calldata description, uint8 decimals, uint256 version) external returns (address);
}
