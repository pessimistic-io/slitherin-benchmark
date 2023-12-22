// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ChainlinkDataFeed} from "./ChainlinkDataFeed.sol";

contract ChainlinkDataFeedFactory {
    
    address public lastChainlinkDataFeed;
    
    event ChainlinkDataFeedCreated(string dataFeedName, address chainlinkDataFeedAddress, address owner, uint256 timestamp);

    function createChainlinkDataFeed(address owner, address authorized, string calldata description, uint8 decimals, uint256 version) external returns (address) {
        
        ChainlinkDataFeed chainlinkDataFeed = new ChainlinkDataFeed(owner, authorized, description, decimals, version);
        lastChainlinkDataFeed = address(chainlinkDataFeed);
        emit ChainlinkDataFeedCreated(description, lastChainlinkDataFeed, owner, block.timestamp);
        
        return lastChainlinkDataFeed;
    }
}

