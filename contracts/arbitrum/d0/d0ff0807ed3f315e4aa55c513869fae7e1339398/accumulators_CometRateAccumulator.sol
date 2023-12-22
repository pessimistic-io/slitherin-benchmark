//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedCometRateAccumulator.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaCometRateAccumulator is AdrastiaVersioning, ManagedCometRateAccumulator {
    struct RateAccumulatorParams {
        IAveragingStrategy averagingStrategy;
        address comet;
        uint256 updateThreshold;
        uint256 minUpdateDelay;
        uint256 maxUpdateDelay;
    }

    string public name;

    constructor(
        string memory name_,
        RateAccumulatorParams memory params
    )
        ManagedCometRateAccumulator(
            params.averagingStrategy,
            params.comet,
            params.updateThreshold,
            params.minUpdateDelay,
            params.maxUpdateDelay
        )
    {
        name = name_;
    }
}

