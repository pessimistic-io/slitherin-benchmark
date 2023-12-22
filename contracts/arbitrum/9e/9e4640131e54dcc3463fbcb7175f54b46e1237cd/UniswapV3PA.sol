//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedUniswapV3PriceAccumulator.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaUniswapV3PA is AdrastiaVersioning, ManagedUniswapV3PriceAccumulator {
    struct PriceAccumulatorParams {
        IAveragingStrategy averagingStrategy;
        address uniswapFactory;
        bytes32 initCodeHash;
        uint24[] poolFees;
        address quoteToken;
        uint256 updateThreshold;
        uint256 minUpdateDelay;
        uint256 maxUpdateDelay;
    }

    string public name;

    constructor(
        string memory name_,
        PriceAccumulatorParams memory params
    )
        ManagedUniswapV3PriceAccumulator(
            params.averagingStrategy,
            params.uniswapFactory,
            params.initCodeHash,
            params.poolFees,
            params.quoteToken,
            params.updateThreshold,
            params.minUpdateDelay,
            params.maxUpdateDelay
        )
    {
        name = name_;
    }
}

