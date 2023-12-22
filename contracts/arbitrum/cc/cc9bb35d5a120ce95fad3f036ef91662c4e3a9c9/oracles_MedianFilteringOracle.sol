//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedMedianFilteringOracle.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaMedianFilteringOracle is AdrastiaVersioning, ManagedMedianFilteringOracle {
    struct MedianFilteringOracleParams {
        IHistoricalOracle source;
        uint256 observationAmount;
        uint256 observationOffset;
        uint256 observationIncrement;
    }

    string public name;

    constructor(
        string memory name_,
        MedianFilteringOracleParams memory params
    )
        ManagedMedianFilteringOracle(
            params.source,
            params.observationAmount,
            params.observationOffset,
            params.observationIncrement
        )
    {
        name = name_;
    }
}

