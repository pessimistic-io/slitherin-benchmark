//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedUniswapV2HarmonicLiquidityAccumulator.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaUniswapV2LA is AdrastiaVersioning, ManagedUniswapV2HarmonicLiquidityAccumulator {
    string public name;

    constructor(
        string memory name_,
        address uniswapFactory_,
        bytes32 initCodeHash_,
        address quoteToken_,
        uint8 decimals_,
        uint256 updateTheshold_,
        uint256 minUpdateDelay_,
        uint256 maxUpdateDelay_
    )
        ManagedUniswapV2HarmonicLiquidityAccumulator(
            uniswapFactory_,
            initCodeHash_,
            quoteToken_,
            decimals_,
            updateTheshold_,
            minUpdateDelay_,
            maxUpdateDelay_
        )
    {
        name = name_;
    }
}

