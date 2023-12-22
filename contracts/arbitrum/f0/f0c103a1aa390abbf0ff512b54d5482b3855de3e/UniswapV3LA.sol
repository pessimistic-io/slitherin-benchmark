//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedUniswapV3LiquidityAccumulator.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaUniswapV3LA is AdrastiaVersioning, ManagedUniswapV3LiquidityAccumulator {
    struct LiquidityAccumulatorParams {
        IAveragingStrategy averagingStrategy;
        address uniswapFactory;
        bytes32 initCodeHash;
        uint24[] poolFees;
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
        ManagedUniswapV3LiquidityAccumulator(
            params.averagingStrategy,
            params.uniswapFactory,
            params.initCodeHash,
            params.poolFees,
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

