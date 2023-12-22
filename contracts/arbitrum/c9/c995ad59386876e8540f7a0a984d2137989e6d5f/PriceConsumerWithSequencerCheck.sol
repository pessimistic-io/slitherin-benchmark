// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

contract PriceConsumerWithSequencerCheck {
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    error SequencerDown();
    error GracePeriodNotOver();

    // Check the sequencer status and return the latest price
    function getLatestPriceWithCheck(
        AggregatorV3Interface priceFeed,
        AggregatorV3Interface sequencerUptimeFeed
    ) public view returns (int, uint256) {
        // prettier-ignore
        (
            /*uint80 roundID*/,
            int256 answer,
            uint256 startedAt,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = sequencerUptimeFeed.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) revert SequencerDown();

        // Make sure the grace period has passed after the sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) revert GracePeriodNotOver();

        // prettier-ignore
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            uint256 timestamp,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();

        return (price, timestamp);
    }
}

