// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./CurveSingleAssetLendingStrategyBase.sol";

/**
 * Adds the arbitrum addresses to the CurveSingleAssetLendingStrategyBase
 */
contract CurveSingleAssetLendingStrategyArbitrum2Pool is
    CurveSingleAssetLendingStrategyBase
{
    string public constant override name =
        "CurveSingleAssetLendingStrategyArbitrum2Pool";
    string public constant override version = "V1";

    // Required Curve Pool (2 Pool)
    address internal constant _crvPool =
        address(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    // Corresponding curve pool token (2Crv)
    address internal constant _crvPoolToken =
        address(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    // Gauge for rewards
    address internal constant _crvPoolGauge =
        address(0xbF7E49483881C76487b0989CD7d9A8239B20CA41);

    // Total number of assets in the pool
    uint8 internal constant _numAssetsInPool = 2;

    // CRV token as rewards
    address internal constant _CRVToken =
        address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);

    // Crv token price feed in underlying
    // This is not yet available on Arbitrum, have handled using backupprice.
    address internal constant _crvPriceFeed = address(0x00);

    // WETH serves as path to convert rewards to underlying
    address internal constant WETH =
        address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // SushiSwap (Uniswap V2 fork) router to liquidate CRV rewards to underlying
    address internal constant _sushiswapRouter =
        address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    // Is router V3 or V2
    bool internal constant _isV3CRVSwapRouter = true;

    address internal constant ZERO_ADDRESS = address(0x00);

    constructor(address _fund)
        public
        CurveSingleAssetLendingStrategyBase(
            _fund,
            _crvPool,
            _crvPoolToken,
            _crvPoolGauge,
            _numAssetsInPool,
            [_CRVToken, _sushiswapRouter, _crvPriceFeed, WETH],
            [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS], // No extra reward token
            false, // 2CRV not wrapped pool
            true // doesn't matter since it is not a wrapped pool
        )
    // solhint-disable-next-line no-empty-blocks
    {

    }
}

