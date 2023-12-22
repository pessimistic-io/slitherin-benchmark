// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {AggregatorV2V3Interface} from "./AggregatorV2V3Interface.sol";
import {ICrv2Pool} from "./ICrv2Pool.sol";

// Libraries
import {Math} from "./Math.sol";

contract Crv2PoolOracle {
    ICrv2Pool public constant CRV_2POOL =
        ICrv2Pool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    AggregatorV2V3Interface internal usdcPriceFeed;
    AggregatorV2V3Interface internal usdtPriceFeed;
    AggregatorV2V3Interface internal sequencerUptimeFeed;

    uint256 public constant HEARTBEAT = 86400;

    uint256 public constant GRACE_PERIOD_TIME = 3600;

    error SequencerDown();
    error GracePeriodNotOver();
    error HeartbeatNotFulfilled();

    /**
     * Network: Arbitrum Mainnet
     * Data Feed: USDC/USD
     * Data Feed Proxy Address: 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3
     * Data Feed: USDT/USD
     * Data Feed Proxy Address: 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7
     * Sequencer Uptime Proxy Address: 0xFdB631F5EE196F0ed6FAa767959853A9F217697D
     */
    constructor() {
        usdcPriceFeed = AggregatorV2V3Interface(
            0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3
        );
        usdtPriceFeed = AggregatorV2V3Interface(
            0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7
        );
        sequencerUptimeFeed = AggregatorV2V3Interface(
            0xFdB631F5EE196F0ed6FAa767959853A9F217697D
        );
    }

    function getUsdcPrice() external view returns (uint256) {
        _checkSequencer();

        (, int256 price, , uint256 updatedAt, ) = usdcPriceFeed
            .latestRoundData();

        if ((block.timestamp - updatedAt) > HEARTBEAT) {
            revert HeartbeatNotFulfilled();
        }

        return uint256(price);
    }

    function getUsdtPrice() external view returns (uint256) {
        _checkSequencer();

        (, int256 price, , uint256 updatedAt, ) = usdtPriceFeed
            .latestRoundData();

        if ((block.timestamp - updatedAt) > HEARTBEAT) {
            revert HeartbeatNotFulfilled();
        }

        return uint256(price);
    }

    function getLpVirtualPrice() external view returns (uint256) {
        return CRV_2POOL.get_virtual_price();
    }

    function getLpPrice() external view returns (uint256) {
        _checkSequencer();

        (, int256 usdcPrice, , uint256 usdcUpdatedAt, ) = usdcPriceFeed
            .latestRoundData();

        (, int256 usdtPrice, , uint256 usdtUpdatedAt, ) = usdtPriceFeed
            .latestRoundData();

        if (
            (block.timestamp - usdcUpdatedAt) > HEARTBEAT ||
            (block.timestamp - usdtUpdatedAt) > HEARTBEAT
        ) {
            revert HeartbeatNotFulfilled();
        }

        uint256 minPrice = Math.min(uint256(usdcPrice), uint256(usdtPrice));
        uint256 virtualPrice = CRV_2POOL.get_virtual_price();

        // minPrice is in 1e8 precision and virtualPrice is 1e18 precision
        // Final price has to be returned in 1e8 precision hence divide by 1e18
        return (minPrice * virtualPrice) / 1e18;
    }

    function _checkSequencer() internal view {
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
    }
}

