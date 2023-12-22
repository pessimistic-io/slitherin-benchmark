//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedUniswapV2LiquidityAccumulator.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaUniswapV2LA is AdrastiaVersioning, ManagedUniswapV2LiquidityAccumulator {
    struct LiquidityAccumulatorParams {
        IAveragingStrategy averagingStrategy;
        address uniswapFactory;
        bytes32 initCodeHash;
        address quoteToken;
        uint8 decimals;
        uint256 updateThreshold;
        uint256 minUpdateDelay;
        uint256 maxUpdateDelay;
    }

    string public name;

    constructor(
        string memory name_,
        LiquidityAccumulatorParams memory params
    )
        ManagedUniswapV2LiquidityAccumulator(
            params.averagingStrategy,
            params.uniswapFactory,
            params.initCodeHash,
            params.quoteToken,
            params.decimals,
            params.updateThreshold,
            params.minUpdateDelay,
            params.maxUpdateDelay
        )
    {
        name = name_;
    }
}

