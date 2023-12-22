// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8;

import "./IUniV3Pool.sol";

library Oracle {
    function getMaxObservationPeriod(IUniV3Pool pool) internal view returns (uint32 maxSecondsAgo) {
        (,, uint16 observationIndex, uint16 observationCardinality,,,) = pool.slot0();
        uint16 oldestIndex = observationIndex == 0 ? observationCardinality + 1 : observationIndex + 1;
        (uint32 oldestBlockTimestamp,,,) = pool.observations(oldestIndex);
        if (oldestBlockTimestamp == 1) {
            (oldestBlockTimestamp,,,) = pool.observations(0);
        }
        maxSecondsAgo = uint32(block.timestamp - oldestBlockTimestamp);
    }

    function getMovingAverage(IUniV3Pool pool, uint32 period) internal view returns (int24 tick) {
        uint32 max = getMaxObservationPeriod(pool);
        if (period > max) period = max;
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = period;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);
        tick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(period)));
    }
}

