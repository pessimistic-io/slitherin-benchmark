//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedPeriodicAggregatorOracle.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaPeriodicAggregatorOracle is AdrastiaVersioning, ManagedPeriodicAggregatorOracle {
    string public name;

    constructor(
        string memory name_,
        AbstractAggregatorOracleParams memory params,
        uint256 period_,
        uint256 granularity_
    ) ManagedPeriodicAggregatorOracle(params, period_, granularity_) {
        name = name_;
    }
}

