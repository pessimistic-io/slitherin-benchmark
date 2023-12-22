// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8;

import "./IUniswapV3Pool.sol";

library UniOracle {
    function getTick(IUniswapV3Pool pool, uint32 duration) public view returns (int24) {
        (uint32 lastTimestamp, int56 oldest) = getOldestTickCumulative(pool);

        if (block.timestamp - lastTimestamp > duration) {
            return getMovingAverage(pool, duration);
        } else {
            int56 latest = getLatestTickCumulative(pool);
            return int24((latest - oldest) / int56(uint56(block.timestamp - lastTimestamp)));
        }
    }

    function getMovingAverage(IUniswapV3Pool pool, uint32 duration) public view returns (int24) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[1] = duration;
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgo);
        return int24((tickCumulatives[0] - tickCumulatives[1]) / int56(uint56(duration)));
    }

    function getMaxMovingAverage(IUniswapV3Pool pool) public view returns (uint32 duration, int24 value) {
        int56 latest = getLatestTickCumulative(pool);
        (uint32 blockTimestamp, int56 oldest) = getOldestTickCumulative(pool);
        duration = uint32(block.timestamp) - blockTimestamp;
        value = int24((latest - oldest) / int56(uint56(duration)));
    }

    function getLatestTickCumulative(IUniswapV3Pool pool) public view returns (int56 tickCumulative) {
        uint32[] memory secondsAgo = new uint32[](1);
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgo);
        tickCumulative = tickCumulatives[0];
    }

    function getOldestTickCumulative(IUniswapV3Pool pool)
        public
        view
        returns (uint32 blockTimestamp, int56 tickCumulative)
    {
        (,, uint16 observationIndex, uint16 observationCardinality,,,) = pool.slot0();
        unchecked {
            observationIndex = (observationIndex + 1) % observationCardinality;
        }
        (blockTimestamp, tickCumulative,,) = pool.observations(observationIndex);
    }
}

