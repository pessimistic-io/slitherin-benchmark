// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./AggregatorV3Interface.sol";
import "./OracleConnector.sol";

contract ChainlinkPriceFeed is OracleConnector {
    AggregatorV3Interface public immutable aggregator;

    function validateTimestamp(uint256) external pure override returns (bool) {
        return true;
    }

    function getPrice() external view override returns (uint256) {
        (, int256 price, , , ) = aggregator.latestRoundData();
        return uint256(price);
    }

    constructor(
        AggregatorV3Interface aggregator_
    ) OracleConnector(aggregator_.description(), aggregator_.decimals()) {
        aggregator = aggregator_;
    }
}

