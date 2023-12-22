// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {AggregatorV2V3Interface} from "./AggregatorV2V3Interface.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {ICrv2Pool} from "./ICrv2Pool.sol";

contract StEthCallPriceOracle is IPriceOracle {
    uint256 public constant GRACE_PERIOD_TIME = 3600;

    error SequencerDown();
    error GracePeriodNotOver();
    error HeartbeatNotFulfilled();

    // stETH/USD
    AggregatorV2V3Interface public constant ST_ETH_PRICE_FEED =
        AggregatorV2V3Interface(0x07C5b924399cc23c24a95c8743DE4006a32b7f2a);

    // wstETH/stETH
    AggregatorV2V3Interface public constant WST_ETH_PRICE_FEED =
        AggregatorV2V3Interface(0xB1552C5e96B312d0Bf8b554186F846C40614a540);

    AggregatorV2V3Interface public constant SEQUENCER_UPTIME_FEED =
        AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);

    /**
     * Network: Arbitrum Mainnet
     * Data Feed: stETH/USD
     * Data Feed Proxy Address: 0x07C5b924399cc23c24a95c8743DE4006a32b7f2a
     * Sequencer Uptime Proxy Address: 0xFdB631F5EE196F0ed6FAa767959853A9F217697D
     */

    /// @notice Returns the collateral price
    function getUnderlyingPrice() external view returns (uint256) {
        return _getPrice(ST_ETH_PRICE_FEED);
    }

    /**
     * Network: Arbitrum Mainnet
     * Data Feed: wstETH/stETH
     * Data Feed Proxy Address: 0xc373B9DB0707fD451Bc56bA5E9b029ba26629DF0
     * Sequencer Uptime Proxy Address: 0xFdB631F5EE196F0ed6FAa767959853A9F217697D
     */
    /// @notice Returns the underlying price
    function getCollateralPrice() external view returns (uint256) {
        return
            (_getPrice(WST_ETH_PRICE_FEED) * _getPrice(ST_ETH_PRICE_FEED)) /
            1e18;
    }

    function _getPrice(AggregatorV2V3Interface _priceFeed)
        private
        view
        returns (uint256)
    {
        (, int256 answer, uint256 startedAt, , ) = SEQUENCER_UPTIME_FEED
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

        (, int256 price, , uint256 updatedAt, ) = _priceFeed.latestRoundData();

        if ((block.timestamp - updatedAt) > 86400) {
            revert HeartbeatNotFulfilled();
        }

        return uint256(price);
    }
}

