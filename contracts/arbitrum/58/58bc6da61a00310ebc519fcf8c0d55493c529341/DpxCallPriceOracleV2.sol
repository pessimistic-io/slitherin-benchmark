// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {AggregatorV2V3Interface} from "./AggregatorV2V3Interface.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

contract DpxCallPriceOracleV2 is IPriceOracle {
    AggregatorV2V3Interface internal priceFeed;
    AggregatorV2V3Interface internal sequencerUptimeFeed;

    uint256 public constant GRACE_PERIOD_TIME = 3600;

    error SequencerDown();
    error GracePeriodNotOver();
    error HeartbeatNotFulfilled();

    /**
     * Network: Arbitrum Mainnet
     * Data Feed: DPX/USD
     * Data Feed Proxy Address: 0xc373B9DB0707fD451Bc56bA5E9b029ba26629DF0
     * Sequencer Uptime Proxy Address: 0xFdB631F5EE196F0ed6FAa767959853A9F217697D
     */
    constructor() {
        priceFeed = AggregatorV2V3Interface(
            0xc373B9DB0707fD451Bc56bA5E9b029ba26629DF0
        );
        sequencerUptimeFeed = AggregatorV2V3Interface(
            0xFdB631F5EE196F0ed6FAa767959853A9F217697D
        );
    }

    /// @notice Returns the collateral price
    function getCollateralPrice() external view returns (uint256) {
        return getUnderlyingPrice();
    }

    /// @notice Returns the underlying price
    function getUnderlyingPrice() public view returns (uint256) {
        (, int256 answer, uint256 startedAt, , ) = sequencerUptimeFeed
            .latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert SequencerDown();
        }

        // Make sure the grace period has passed after the sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert GracePeriodNotOver();
        }

        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();

        if ((block.timestamp - updatedAt) > 86400) {
            revert HeartbeatNotFulfilled();
        }

        return uint256(price);
    }
}

