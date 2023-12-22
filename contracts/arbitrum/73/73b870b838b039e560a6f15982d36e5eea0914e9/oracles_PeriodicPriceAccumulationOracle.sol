//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedPeriodicPriceAccumulationOracle.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaPeriodicPriceAccumulationOracle is AdrastiaVersioning, ManagedPeriodicPriceAccumulationOracle {
    struct PeriodicAccumulationOracleParams {
        address priceAccumulator;
        address quoteToken;
        uint256 period;
        uint256 granularity;
        uint112 staticTokenLiquidity;
        uint112 staticQuoteTokenLiquidity;
        uint8 liquidityDecimals;
    }

    string public name;

    constructor(
        string memory name_,
        PeriodicAccumulationOracleParams memory params
    )
        ManagedPeriodicPriceAccumulationOracle(
            params.priceAccumulator,
            params.quoteToken,
            params.period,
            params.granularity,
            params.staticTokenLiquidity,
            params.staticQuoteTokenLiquidity,
            params.liquidityDecimals
        )
    {
        name = name_;
    }
}

