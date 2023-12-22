// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Math} from "./Math.sol";
import {UniV3Wrapper} from "./UniV3Wrapper.sol";

contract UniV3WrapperActive is UniV3Wrapper {
    uint24 public distanceLower;
    uint24 public distanceUpper;
    uint24 public buffer;
    uint32 public maDuration;

    event RangeUpdated(int24 tickLower, int24 tickUpper);
    event RangeParamsUpdated(uint24 distanceLower, uint24 distanceUpper, uint24 buffer, uint32 maDuration);

    constructor(address uniV3Pool, uint24 _distanceLower, uint24 _distanceUpper, uint32 _maDuration, uint24 _buffer)
        UniV3Wrapper(uniV3Pool, 0, 0)
    {
        distanceLower = _distanceLower;
        distanceUpper = _distanceUpper;
        buffer = _buffer;
        maDuration = _maDuration;
        (tickLower, tickUpper,) = getIdealRange();
    }

    function setRangeParameters(uint24 _distanceLower, uint24 _distanceUpper, uint24 _buffer, uint32 _maDuration)
        external
        requireSender(controller)
    {
        distanceLower = _distanceLower;
        distanceUpper = _distanceUpper;
        buffer = _buffer;
        maDuration = _maDuration;
        emit RangeParamsUpdated(_distanceLower, _distanceUpper, _buffer, _maDuration);
    }

    function getIdealRange() public view returns (int24 targetLower, int24 targetUpper, bool needsToUpdate) {
        int24 tick = getMovingAverage(maDuration);
        int24 tickSpacing = pool().tickSpacing();
        targetLower = tick - int24(distanceLower);
        targetUpper = tick + int24(distanceUpper);
        targetLower = targetLower - (targetLower % tickSpacing);
        targetUpper = targetUpper - (targetUpper % tickSpacing);
        needsToUpdate = Math.diff(tickLower, targetLower) > buffer || Math.diff(tickUpper, targetUpper) > buffer;
    }

    function updateRange() external stablePrice returns (uint256 amount0, uint256 amount1, uint128 liquidityAdded) {
        (int24 newLower, int24 newUpper, bool needsToUpdate) = getIdealRange();
        require(needsToUpdate, "Range does not need to be updated");
        _removeLiquidity(totalLiquidity, address(this));
        (tickLower, tickUpper) = (newLower, newUpper);
        emit RangeUpdated(newLower, newUpper);
        (amount0, amount1, liquidityAdded,) = _addMaxLiquidity(0);
    }
}

