// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./AggregatorV2V3Interface.sol";
import "./OracleConnector.sol";

contract ChainlinkPriceFeed is OracleConnector {
    AggregatorV2V3Interface public immutable aggregator;

    function getRoundData(
        uint256 roundId
    ) external view override returns (uint256, uint256, uint256, uint256, uint256) {
        require(roundId <= type(uint80).max, "ChainlinkPriceFeed: Round id is invalid");
        (, int256 answer, uint256 startedAt, uint256 updatedAt, uint256 answeredInRound) = aggregator.getRoundData(
            uint80(roundId)
        );
        require(answer >= 0, "ChainlinkPriceFeed: Answer is negative");
        return (roundId, uint256(answer), startedAt, updatedAt, answeredInRound);
    }

    function latestRoundData() external view override returns (uint256, uint256, uint256, uint256, uint256) {
        (uint256 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint256 answeredInRound) = aggregator
            .latestRoundData();
        require(answer >= 0, "ChainlinkPriceFeed: Answer is negative");
        return (roundId, uint256(answer), startedAt, updatedAt, answeredInRound);
    }

    function latestRound() external view override returns (uint256) {
        return aggregator.latestRound();
    }

    function validateTimestamp(uint256) external pure override returns (bool) {
        return true;
    }

    constructor(
        AggregatorV2V3Interface aggregator_
    ) OracleConnector(aggregator_.description(), aggregator_.decimals()) {
        aggregator = aggregator_;
    }
}

