// SPDX-License-Identifier: None
pragma solidity =0.8.12;

import {IUniswapV3PoolDeployer} from "./IUniswapV3PoolDeployer.sol";

import {AlcorCallOption} from "./AlcorCallOption.sol";

contract AlcorOptionPoolDeployer {
    struct Parameters {
        address factory;
        uint256 strikePrice;
        uint256 expiry;
        address realUniswapV3PoolAddress;
        address conjugatedUniswapV3PoolAddress;
        address token0;
        address token1;
    }

    Parameters public parameters;

    function deployCallOption(
        address factory,
        uint256 strikePrice,
        uint256 expiry,
        address realUniswapV3PoolAddress,
        address conjugatedUniswapV3PoolAddress,
        address token0,
        address token1
    ) internal virtual returns (address pool) {
        parameters = Parameters({
            factory: factory,
            strikePrice: strikePrice,
            expiry: expiry,
            realUniswapV3PoolAddress: realUniswapV3PoolAddress,
            conjugatedUniswapV3PoolAddress: conjugatedUniswapV3PoolAddress,
            token0: token0,
            token1: token1
        });
        pool = address(
            new AlcorCallOption{
                salt: keccak256(abi.encode(strikePrice, expiry, realUniswapV3PoolAddress, token0, token1))
            }()
        );
        delete parameters;
    }
}

