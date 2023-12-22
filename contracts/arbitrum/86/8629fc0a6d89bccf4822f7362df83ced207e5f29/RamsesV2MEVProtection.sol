// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./OracleLibrary.sol";

import "./IMEVProtection.sol";

contract RamsesV2MEVProtection is IMEVProtection {
    struct SecurityParams {
        uint32[] secondsAgos;
        int24 maxDeviation;
    }

    function ensureNoMEV(address pool, bytes memory data) external view override {
        SecurityParams memory params = abi.decode(data, (SecurityParams));
        int24[] memory averageTicks = new int24[](params.secondsAgos.length);
        for (uint256 i = 0; i < params.secondsAgos.length; i++) {
            bool withFail;
            (averageTicks[i], , withFail) = OracleLibrary.consult(pool, params.secondsAgos[i]);
            if (withFail) revert NotEnoughObservations();
        }
        for (uint256 i = 1; i < averageTicks.length; i++) {
            int24 delta = averageTicks[i] - averageTicks[i - 1];
            if (delta < 0) delta = -delta;
            if (delta > params.maxDeviation) {
                revert PoolIsNotStable();
            }
        }
        {
            (, int24 spotTick, , , , , ) = IRamsesV2Pool(pool).slot0();
            int24 lastAverageTick = averageTicks[0];
            int24 delta = spotTick - lastAverageTick;
            if (delta < 0) delta = -delta;
            if (delta > params.maxDeviation) {
                revert PoolIsNotStable();
            }
        }
    }
}

