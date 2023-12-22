// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

interface IKyberPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swapFeeUnits() external view returns (uint24);
    function tickDistance() external view returns (int24);
    function getPoolState()
        external
        view
        returns (uint160 sqrtP, int24 currentTick, int24 nearestCurrentTick, bool locked);
    function initializedTicks(int24 tick) external view returns (int24 previous, int24 next);
}

