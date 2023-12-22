// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8;

import "./FullMath.sol";

library FeeMath {
    function getFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint256 l_feeGrowthOutside0X128,
        uint256 l_feeGrowthOutside1X128,
        uint256 u_feeGrowthOutside0X128,
        uint256 u_feeGrowthOutside1X128
    ) internal pure returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = l_feeGrowthOutside0X128;
            feeGrowthBelow1X128 = l_feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - l_feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - l_feeGrowthOutside1X128;
        }
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = u_feeGrowthOutside0X128;
            feeGrowthAbove1X128 = u_feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - u_feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - u_feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    function getPendingFees(
        uint128 liquidity,
        uint256 feeGrowthInside0Last,
        uint256 feeGrowthInside1Last,
        uint256 feeGrowthInside0,
        uint256 feeGrowthInside1
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        amount0 =
            FullMath.mulDiv(feeGrowthInside0 - feeGrowthInside0Last, liquidity, 0x100000000000000000000000000000000);
        amount1 =
            FullMath.mulDiv(feeGrowthInside1 - feeGrowthInside1Last, liquidity, 0x100000000000000000000000000000000);
    }
}

