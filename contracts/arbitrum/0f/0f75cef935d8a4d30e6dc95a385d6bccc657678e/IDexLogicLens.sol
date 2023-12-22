// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";

/// @title IDexLogicLens - DexLogicLens interface
interface IDexLogicLens {
    // =========================
    // Getters
    // =========================

    /// @notice Gets the current sqrt price from the pool
    /// @param dexPool: The address of the pool
    /// @return The current sqrt price
    function getCurrentSqrtRatioX96(
        IUniswapV3Pool dexPool
    ) external view returns (uint160);

    /// @notice Gets the current liquidity of a specific position
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @return The liquidity of the position
    function getLiquidity(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager
    ) external view returns (uint128);

    /// @notice Gets the number of accumulated fees in a specific position
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @param dexFactory: The Dex Factory contract instance
    /// @return fee0: The accumulated fee for token0
    /// @return fee1: The accumulated fee for token1
    function fees(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256, uint256);

    /// @notice Gets the total value locked in a specific position
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @param dexFactory: The Dex Factory contract instance
    /// @return total0: The total amount of token0
    /// @return total1: The total amount of token1
    function tvl(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256, uint256);

    /// @notice Gets the principal amounts locked in a specific position
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @param dexFactory: The Dex Factory contract instance
    /// @return principal0: The principal amount of token0
    /// @return principal1: The principal amount of token1
    function principal(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256, uint256);

    /// @notice Gets the total value locked, expressed in token1 terms
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @param dexFactory: The Dex Factory contract instance
    /// @return The total value locked in terms of token1
    function tvlInToken1(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256);

    /// @notice Gets the total value locked, expressed in token0 terms
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @param dexFactory: The Dex Factory contract instance
    /// @return The total value locked in terms of token0
    function tvlInToken0(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256);

    /// @notice Calculates the correlation of token0 to token1
    /// @param amount0: The amount of token0
    /// @param amount1: The amount of token1
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @param dexFactory: The Dex Factory contract instance
    /// @return res The calculated correlation of token0 to token1 with a base of e18
    /// @dev The result is an uint with e18 base, i.e. res = px / (px + y) * 10^18
    /// where:
    ///  x - amount0
    ///  y - amount1
    ///  p - current spot price
    function getRE18(
        uint256 amount0,
        uint256 amount1,
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256 res);

    /// @notice Calculates the correlation of token0 to token1 within a tick range based on total pool liquidity
    /// @param nftId: The Id of the NFT representing the position
    /// @param dexNftPositionManager: The Nonfungible Position Manager contract instance
    /// @param dexFactory: The Dex Factory contract instance
    /// @return res The calculated correlation of token0 to token1 within the tick range
    /// @dev The result is an uint with e18 base, i.e. res = px / (px + y) * 10^18
    /// where:
    ///  x - amount0 for total pool liquidity
    ///  y - amount1 for total pool liquidity
    ///  p - current spot price
    function getTargetRE18ForTickRange(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager,
        IUniswapV3Factory dexFactory
    ) external view returns (uint256 res);

    /// @notice Calculates the correlation of token0 to token1 within a specified tick range
    /// @param minTick: The minimum tick of the range
    /// @param maxTick: The maximum tick of the range
    /// @param dexPool: The Dex Pool contract instance
    /// @return res The calculated correlation of token0 to token1 within the specified tick range
    /// @dev The result is an uint with e18 base, i.e. res = px / (px + y) * 10^18
    /// where:
    ///  x - amount0 for total pool liquidity
    ///  y - amount1 for total pool liquidity
    ///  p - current spot price
    function getTargetRE18ForTickRange(
        int24 minTick,
        int24 maxTick,
        IUniswapV3Pool dexPool
    ) external view returns (uint256 res);

    /// @notice Calculates the required amount of token1 to achieve a target correlation after a swap
    /// @param sqrtPriceX96: The current square root price
    /// @param amount0: The amount of token0
    /// @param amount1: The amount of token1
    /// @param targetRE18: The desired correlation with a base of e18
    /// @param poolFeeE6: The fee associated with the pool
    /// @return The amount of token1 needed to achieve the target correlation
    function token1AmountForTargetRE18(
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        uint256 targetRE18,
        uint24 poolFeeE6
    ) external pure returns (uint256);

    /// @notice Calculates the required amount of token0 to achieve a target correlation after a swap
    /// @param sqrtPriceX96: The current square root price
    /// @param amount1: The amount of token1
    /// @param targetRE18: The desired correlation with a base of e18
    /// @return The amount of token0 needed to achieve the target correlation
    function token0AmountForTargetRE18(
        uint160 sqrtPriceX96,
        uint256 amount1,
        uint256 targetRE18
    ) external pure returns (uint256);
}

