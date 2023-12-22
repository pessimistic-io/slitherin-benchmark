// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";

import {PositionValueMod} from "./PositionValueMod.sol";
import {DexLogicLib} from "./DexLogicLib.sol";

import {IDexLogicLens} from "./IDexLogicLens.sol";

/// @title DexLogicLens
/// @notice A lens contract to extract information from Dexes
contract DexLogicLens is IDexLogicLens {
    // =========================
    // Getters
    // =========================

    /// @inheritdoc IDexLogicLens
    function getCurrentSqrtRatioX96(
        IUniswapV3Pool dexPool
    ) external view returns (uint160) {
        return DexLogicLib.getCurrentSqrtRatioX96(dexPool);
    }

    /// @inheritdoc IDexLogicLens
    function getLiquidity(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager
    ) external view returns (uint128) {
        return DexLogicLib.getLiquidity(nftId, dexNftPositionManager);
    }

    /// @inheritdoc IDexLogicLens
    function fees(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256, uint256) {
        (, , , , , , IUniswapV3Pool dexPool) = _getData(
            nftId,
            dexNftPositionManager,
            dexFactory
        );

        return DexLogicLib.fees(nftId, dexPool, dexNftPositionManager);
    }

    /// @inheritdoc IDexLogicLens
    function tvl(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256, uint256) {
        (, , , , , , IUniswapV3Pool dexPool) = _getData(
            nftId,
            dexNftPositionManager,
            dexFactory
        );

        return DexLogicLib.tvl(nftId, dexPool, dexNftPositionManager);
    }

    /// @inheritdoc IDexLogicLens
    function principal(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256, uint256) {
        (, , , , , , IUniswapV3Pool dexPool) = _getData(
            nftId,
            dexNftPositionManager,
            dexFactory
        );

        return DexLogicLib.principal(nftId, dexPool, dexNftPositionManager);
    }

    /// @inheritdoc IDexLogicLens
    function tvlInToken1(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256) {
        (, , , , , , IUniswapV3Pool dexPool) = _getData(
            nftId,
            dexNftPositionManager,
            dexFactory
        );

        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(dexPool);

        (uint256 amount0, uint256 amount1) = PositionValueMod.total(
            dexNftPositionManager,
            nftId,
            sqrtPriceX96,
            dexPool
        );
        uint256 amount0InToken1 = DexLogicLib.getAmount0InToken1(
            sqrtPriceX96,
            amount0
        );
        unchecked {
            return amount0InToken1 + amount1;
        }
    }

    /// @inheritdoc IDexLogicLens
    function tvlInToken0(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256) {
        (, , , , , , IUniswapV3Pool dexPool) = _getData(
            nftId,
            dexNftPositionManager,
            dexFactory
        );

        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(dexPool);

        (uint256 amount0, uint256 amount1) = PositionValueMod.total(
            dexNftPositionManager,
            nftId,
            sqrtPriceX96,
            dexPool
        );
        uint256 amount1InToken0 = DexLogicLib.getAmount1InToken0(
            sqrtPriceX96,
            amount1
        );
        unchecked {
            return amount1InToken0 + amount0;
        }
    }

    /// @inheritdoc IDexLogicLens
    function getRE18(
        uint256 amount0,
        uint256 amount1,
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256 res) {
        (, , , , , , IUniswapV3Pool dexPool) = _getData(
            nftId,
            dexNftPositionManager,
            dexFactory
        );

        // get the sqrt ratio
        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(dexPool);

        res = DexLogicLib.getRE18(amount0, amount1, sqrtPriceX96);
    }

    /// @inheritdoc IDexLogicLens
    function getTargetRE18ForTickRange(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256 res) {
        (
            ,
            ,
            ,
            int24 minTick,
            int24 maxTick,
            ,
            IUniswapV3Pool dexPool
        ) = _getData(nftId, dexNftPositionManager, dexFactory);

        // get the sqrt ratio
        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(dexPool);

        res = DexLogicLib.getTargetRE18ForTickRange(
            minTick,
            maxTick,
            dexPool.liquidity(),
            sqrtPriceX96
        );
    }

    /// @inheritdoc IDexLogicLens
    function getTargetRE18ForTickRange(
        int24 minTick,
        int24 maxTick,
        IUniswapV3Pool dexPool
    ) external view returns (uint256 res) {
        // get the sqrt ratio
        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(dexPool);

        res = DexLogicLib.getTargetRE18ForTickRange(
            minTick,
            maxTick,
            dexPool.liquidity(),
            sqrtPriceX96
        );
    }

    /// @inheritdoc IDexLogicLens
    function token1AmountForTargetRE18(
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        uint256 targetRE18,
        uint24 poolFeeE6
    ) external pure returns (uint256) {
        return
            DexLogicLib.token1AmountAfterSwapForTargetRE18(
                sqrtPriceX96,
                amount0,
                amount1,
                targetRE18,
                poolFeeE6
            );
    }

    /// @inheritdoc IDexLogicLens
    function token0AmountForTargetRE18(
        uint160 sqrtPriceX96,
        uint256 amount1,
        uint256 targetRE18
    ) external pure returns (uint256) {
        return
            DexLogicLib.token0AmountAfterSwapForTargetRE18(
                sqrtPriceX96,
                amount1,
                targetRE18
            );
    }

    /// @dev This is an internal function to get data associated with a specific NFT position
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @param dexFactory: The Dex Factory contract instance
    /// @return token0 The address of token0
    /// @return token1 The address of token1
    /// @return poolFee The fee of the pool
    /// @return tickLower The lower bound of the position's tick range
    /// @return tickUpper The upper bound of the position's tick range
    /// @return liquidity The liquidity of the position
    /// @return dexPool The associated Dex pool for the position
    function _getData(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    )
        private
        view
        returns (
            address token0,
            address token1,
            uint24 poolFee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            IUniswapV3Pool dexPool
        )
    {
        (token0, token1, poolFee, tickLower, tickUpper, liquidity) = DexLogicLib
            .getNftData(nftId, dexNftPositionManager);
        dexPool = DexLogicLib.dexPool(token0, token1, poolFee, dexFactory);
    }
}

