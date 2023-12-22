// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

library DpmmLinearPricing {

    int256 constant ONE = 1e18;

    function calculateMarkPrice(
        int256 theoreticalPrice,
        int256 K,
        int256 tradersNetVolume
    ) internal pure returns (int256)
    {
        return theoreticalPrice * (ONE + K * tradersNetVolume / ONE) / ONE;
    }

    function calculateCost(
        int256 theoreticalPrice,
        int256 K,
        int256 tradersNetVolume,
        int256 tradeVolume
    ) internal pure returns (int256)
    {
        int256 r = ((tradersNetVolume + tradeVolume) ** 2 - tradersNetVolume ** 2) / ONE * K / ONE / 2 + tradeVolume;
        return theoreticalPrice * r / ONE;
    }

}

