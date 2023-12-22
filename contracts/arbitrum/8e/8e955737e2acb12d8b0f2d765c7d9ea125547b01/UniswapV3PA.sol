//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./ManagedUniswapV3PriceAccumulator.sol";

import "./PythiaVersioning.sol";

contract PythiaUniswapV3PA is PythiaVersioning, ManagedUniswapV3PriceAccumulator {
    string public name;

    constructor(
        string memory name_,
        address uniswapFactory_,
        bytes32 initCodeHash_,
        uint24[] memory poolFees_,
        address quoteToken_,
        uint256 updateTheshold_,
        uint256 minUpdateDelay_,
        uint256 maxUpdateDelay_
    )
        ManagedUniswapV3PriceAccumulator(
            uniswapFactory_,
            initCodeHash_,
            poolFees_,
            quoteToken_,
            updateTheshold_,
            minUpdateDelay_,
            maxUpdateDelay_
        )
    {
        name = name_;
    }
}

