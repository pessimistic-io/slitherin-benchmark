//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedAaveV3RateAccumulator.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaAaveV3RateAccumulator is AdrastiaVersioning, ManagedAaveV3RateAccumulator {
    struct RateAccumulatorParams {
        IAveragingStrategy averagingStrategy;
        address aaveV3;
        address quoteToken;
        uint256 updateThreshold;
        uint256 minUpdateDelay;
        uint256 maxUpdateDelay;
    }

    string public name;

    constructor(
        string memory name_,
        RateAccumulatorParams memory params
    )
        ManagedAaveV3RateAccumulator(
            params.averagingStrategy,
            params.aaveV3,
            params.quoteToken,
            params.updateThreshold,
            params.minUpdateDelay,
            params.maxUpdateDelay
        )
    {
        name = name_;
    }
}

