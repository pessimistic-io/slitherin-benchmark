//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedPriceVolatilityOracle.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaPriceVolatilityOracle is AdrastiaVersioning, ManagedPriceVolatilityOracle {
    struct PriceVolatilityOracleParams {
        VolatilityOracleView volatilityView;
        IHistoricalOracle source;
        uint256 observationAmount;
        uint256 observationOffset;
        uint256 observationIncrement;
        uint256 meanType;
    }

    string public name;

    constructor(
        string memory name_,
        PriceVolatilityOracleParams memory params
    )
        ManagedPriceVolatilityOracle(
            params.volatilityView,
            params.source,
            params.observationAmount,
            params.observationOffset,
            params.observationIncrement,
            params.meanType
        )
    {
        name = name_;
    }
}

