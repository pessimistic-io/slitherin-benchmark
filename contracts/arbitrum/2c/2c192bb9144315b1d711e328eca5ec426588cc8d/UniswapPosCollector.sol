// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Strings.sol";

import "./IBaseCollector.sol";

import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./PositionValue.sol";

contract UniswapPosCollector is IBaseCollector {
    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Factory public immutable factory;

    constructor(INonfungiblePositionManager positionManager_) {
        positionManager = positionManager_;
        factory = IUniswapV3Factory(positionManager.factory());
    }

    function collect(
        address vault,
        address
    ) external view returns (Response memory response, address[] memory underlyingTokens) {
        response.tvl = new uint256[](2);
        response.unclaimedFees = new uint256[](2);
        uint256 uniV3Nft = uint160(vault);

        (, , address token0, address token1, uint24 fee, , , , , , , ) = positionManager.positions(uniV3Nft);

        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        (response.tvl[0], response.tvl[1]) = PositionValue.total(positionManager, uniV3Nft, sqrtRatioX96, pool);
        (response.unclaimedFees[0], response.unclaimedFees[1]) = PositionValue.fees(positionManager, uniV3Nft, pool);

        underlyingTokens = new address[](2);
        underlyingTokens[0] = token0;
        underlyingTokens[1] = token1;
    }
}

