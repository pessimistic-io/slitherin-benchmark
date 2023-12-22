// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IUniV3Vault} from "./IUniV3Vault.sol";

import "./univ3_INonfungiblePositionManager.sol";
import "./univ3_IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";

import "./IBaseFeesCollector.sol";

import "./PositionValue.sol";

contract UniV3FeesCollector is IBaseFeesCollector {
    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Factory public immutable factory;

    constructor(INonfungiblePositionManager positionManager_) {
        positionManager = positionManager_;
        factory = IUniswapV3Factory(positionManager.factory());
    }

    function collectFeesData(
        address vault
    ) external view override returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](2);
        amounts = new uint256[](2);
        uint256 positionNft = IUniV3Vault(vault).uniV3Nft();

        (, , address token0, address token1, uint24 fee, , , , , , , ) = positionManager.positions(positionNft);
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));

        (amounts[0], amounts[1]) = PositionValue.fees(positionManager, positionNft, pool);

        tokens[0] = token0;
        tokens[1] = token1;
    }
}

