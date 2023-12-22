//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedPeriodicAccumulationOracle.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaPeriodicAccumulationOracle is AdrastiaVersioning, ManagedPeriodicAccumulationOracle {
    struct PeriodicAccumulationOracleParams {
        address liquidityAccumulator;
        address priceAccumulator;
        address quoteToken;
        uint256 period;
        uint256 granularity;
    }

    string public name;

    constructor(
        string memory name_,
        PeriodicAccumulationOracleParams memory params
    )
        ManagedPeriodicAccumulationOracle(
            params.liquidityAccumulator,
            params.priceAccumulator,
            params.quoteToken,
            params.period,
            params.granularity
        )
    {
        name = name_;
    }
}

