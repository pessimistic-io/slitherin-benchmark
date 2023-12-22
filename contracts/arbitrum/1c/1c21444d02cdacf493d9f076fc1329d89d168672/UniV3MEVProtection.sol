// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./OracleLibrary.sol";

import "./IMEVProtection.sol";

contract UniV3MEVProtection is IMEVProtection {
    struct SecurityParams {
        uint16[] observationsAgo;
        int24 maxDeviation;
    }

    function ensureNoMEV(address pool, bytes memory data) external view override {
        SecurityParams memory params = abi.decode(data, (SecurityParams));
        int24[] memory averageTicks = OracleLibrary.consultByObservations(pool, params.observationsAgo);
        for (uint256 i = 1; i < averageTicks.length; i++) {
            int24 delta = averageTicks[i] - averageTicks[i - 1];
            if (delta < 0) delta = -delta;
            if (delta > params.maxDeviation) {
                revert PoolIsNotStable();
            }
        }
        {
            (, int24 spotTick, , , , , ) = IUniswapV3Pool(pool).slot0();
            int24 lastAverageTick = averageTicks[averageTicks.length - 1];
            int24 delta = spotTick - lastAverageTick;
            if (delta < 0) delta = -delta;
            if (delta > params.maxDeviation) {
                revert PoolIsNotStable();
            }
        }
    }
}

