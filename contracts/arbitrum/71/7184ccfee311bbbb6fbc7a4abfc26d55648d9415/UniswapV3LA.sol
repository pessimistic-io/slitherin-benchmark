//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedUniswapV3HarmonicLiquidityAccumulator.sol";

import "./AdrastiaVersioning.sol";

contract AdrastiaUniswapV3LA is AdrastiaVersioning, ManagedUniswapV3HarmonicLiquidityAccumulator {
    string public name;

    constructor(
        string memory name_,
        address uniswapFactory_,
        bytes32 initCodeHash_,
        uint24[] memory poolFees_,
        address quoteToken_,
        uint8 decimals_,
        uint256 updateTheshold_,
        uint256 minUpdateDelay_,
        uint256 maxUpdateDelay_
    )
        ManagedUniswapV3HarmonicLiquidityAccumulator(
            uniswapFactory_,
            initCodeHash_,
            poolFees_,
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

