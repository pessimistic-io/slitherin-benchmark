//SPDX-License-Identifier: Unlicense
pragma solidity =0.7.6;
pragma abicoder v2;

import "./TickMath.sol";
import "./LiquidityAmounts.sol";

library TidePoolMath {

    int24 internal constant MAX_TICK = 887272;
    int24 internal constant MIN_TICK = -MAX_TICK;

    // calculates how much of the tick window is above vs below
    function calculateWindow(int24 tick, int24 tickSpacing, int24 window, uint8 bias) public pure returns (int24 tickUpper, int24 tickLower) {
        require(bias >= 0 && bias <= 100,"BB");
        window = window < 2 ? 2 : window;
        int24 windowSize = window * tickSpacing;

        tickUpper = (tick + windowSize * bias / 100);
        tickLower = (tick - windowSize * (100-bias) / 100);

        // fix some corner cases
        if(tickUpper < tick) tickUpper = tick;
        if(tickLower > tick) tickLower = tick;
        if(tickUpper > MAX_TICK) tickUpper = (MAX_TICK / tickSpacing - 1) * tickSpacing;
        if(tickLower < MIN_TICK) tickLower = (MIN_TICK / tickSpacing + 1) * tickSpacing;

        // make sure these are valid ticks
        tickUpper = tickUpper / tickSpacing * tickSpacing;
        tickLower = tickLower / tickSpacing * tickSpacing;
    }

    // find the greater ratio: a:b or c:d. From 0 - 100.
    function zeroIsLessUsed(uint256 a, uint256 b, uint256 c, uint256 d) public pure returns (bool) {
        require(a <= b && c <= d,"Illegal inputs");
        uint256 first = a > 0 ? a * 100 / b : 0;
        uint256 second = c > 0 ? c * 100 / d : 0;
        return  first <= second ? true : false;
    }

    // window size grows by 4 ticks every rebalance, but shrinks 1 tick per day if it stays within the range.
    function getTickWindowSize(int24 _previousWindow, uint256 _lastRebalance, bool _outOfRange) public view returns (int24 window) {
        uint256 diff = block.timestamp - _lastRebalance;
        window = _outOfRange ? _previousWindow + 4 : _previousWindow - int24(diff / 1 days);
        window = window < 2 ? 2 : window;
    }
}
