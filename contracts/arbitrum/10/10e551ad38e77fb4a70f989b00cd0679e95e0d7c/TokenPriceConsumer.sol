// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./Ownable.sol";
import "./AggregatorV3Interface.sol";

contract TokenPriceConsumer is Ownable {
    mapping(address => AggregatorV3Interface) private tokenPriceFeeds;

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses) {
        require(tokenAddresses.length == priceFeedAddresses.length, "Arrays length mismatch");

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            tokenPriceFeeds[tokenAddresses[i]] = AggregatorV3Interface(priceFeedAddresses[i]);
        }
    }

    function addPriceFeed(address tokenAddress, address priceFeedAddress) public onlyOwner {
        require(priceFeedAddress != address(0), "Invalid address");
        require(address(tokenPriceFeeds[tokenAddress]) == address(0), "PriceFeed already exist");
        tokenPriceFeeds[tokenAddress] = AggregatorV3Interface(priceFeedAddress);
    }

    function removePriceFeed(address tokenAddress) public onlyOwner {
        require(address(tokenPriceFeeds[tokenAddress]) != address(0), "PriceFeed already exist");
        tokenPriceFeeds[tokenAddress] = AggregatorV3Interface(address(0));
    }

    function getTokenPrice(address tokenAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = tokenPriceFeeds[tokenAddress];
        require(address(priceFeed) != address(0), "Price feed not found");

        (, int256 answer, , , ) = priceFeed.latestRoundData();
        // Token price might need additional scaling based on decimals
        return uint256(answer);
    }

    function decimals(address tokenAddress) public view returns (uint8) {
        AggregatorV3Interface priceFeed = tokenPriceFeeds[tokenAddress];
        require(address(priceFeed) != address(0), "Price feed not found");
        return priceFeed.decimals();
    }
}
