//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedUniswapV2PriceAccumulator.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaUniswapV2PA is AdrastiaVersioning, ManagedUniswapV2PriceAccumulator {
    struct PriceAccumulatorParams {
        IAveragingStrategy averagingStrategy;
        address uniswapFactory;
        bytes32 initCodeHash;
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
        ManagedUniswapV2PriceAccumulator(
            params.averagingStrategy,
            params.uniswapFactory,
            params.initCodeHash,
            params.quoteToken,
            params.updateThreshold,
            params.minUpdateDelay,
            params.maxUpdateDelay
        )
    {
        name = name_;
    }
}

