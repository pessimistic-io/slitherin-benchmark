// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "./IERC20.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";

import { Math } from "./Math.sol";

import { FixedPoint128 } from "./FixedPoint128.sol";
import { FullMath } from "./FullMath.sol";

import { IClearingHouseStructures } from "./IClearingHouseStructures.sol";
import { IVQuote } from "./IVQuote.sol";
import { IVToken } from "./IVToken.sol";
import { IVPoolWrapper } from "./IVPoolWrapper.sol";

import { PriceMath } from "./PriceMath.sol";
import { SafeCast } from "./libraries_SafeCast.sol";
import { SignedMath } from "./SignedMath.sol";
import { SignedFullMath } from "./SignedFullMath.sol";
import { UniswapV3PoolHelper } from "./UniswapV3PoolHelper.sol";
import { Block } from "./Block.sol";
import { SafeCast } from "./libraries_SafeCast.sol";

/// @title Protocol storage functions
/// @dev This is used as main storage interface containing protocol info
library Protocol {
    using FullMath for uint256;
    using PriceMath for uint160;
    using PriceMath for uint256;
    using SignedMath for int256;
    using SignedFullMath for int256;
    using SafeCast for uint256;
    using UniswapV3PoolHelper for IUniswapV3Pool;
    using SafeCast for uint256;

    using Protocol for Protocol.Info;

    struct PriceCache {
        uint32 updateBlockNumber;
        uint224 virtualPriceX128;
        uint224 realPriceX128;
        bool isDeviationBreached;
    }
    struct Info {
        // poolId => PoolInfo
        mapping(uint32 => IClearingHouseStructures.Pool) pools;
        // collateralId => CollateralInfo
        mapping(uint32 => IClearingHouseStructures.Collateral) collaterals;
        // iterable and increasing list of pools (used for admin functions)
        uint32[] poolIds;
        // settlement token (default collateral)
        IERC20 settlementToken;
        // virtual quote token (sort of fake USDC), is always token1 in uniswap pools
        IVQuote vQuote;
        // accounting settings
        IClearingHouseStructures.LiquidationParams liquidationParams;
        uint256 minRequiredMargin;
        uint256 removeLimitOrderFee;
        uint256 minimumOrderNotional;
        // price cache
        mapping(uint32 => PriceCache) priceCache;
        // reserved for adding slots in future
        uint256[100] _emptySlots;
    }

    function updatePoolPriceCache(Protocol.Info storage protocol, uint32 poolId) internal {
        uint32 blockNumber = Block.number();

        PriceCache storage poolPriceCache = protocol.priceCache[poolId];
        if (poolPriceCache.updateBlockNumber == blockNumber) {
            return;
        }

        uint256 realPriceX128 = protocol.getRealTwapPriceX128(poolId);
        uint256 virtualPriceX128 = protocol.getVirtualTwapPriceX128(poolId);

        // In case the price is breaching the Q224 limit, we do not cache it
        uint256 Q224 = 1 << 224;
        if (realPriceX128 >= Q224 || virtualPriceX128 >= Q224) {
            return;
        }

        uint16 maxDeviationBps = protocol.pools[poolId].settings.maxVirtualPriceDeviationRatioBps;
        if (
            // if virtual price is too off from real price then screw that, we'll just use real price
            (int256(realPriceX128) - int256(virtualPriceX128)).absUint() > realPriceX128.mulDiv(maxDeviationBps, 1e4)
        ) {
            poolPriceCache.isDeviationBreached = true;
        } else {
            poolPriceCache.isDeviationBreached = false;
        }
        poolPriceCache.realPriceX128 = realPriceX128.toUint224();
        poolPriceCache.virtualPriceX128 = virtualPriceX128.toUint224();
        poolPriceCache.updateBlockNumber = blockNumber;
    }

    /// @notice gets the uniswap v3 pool address for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return UniswapV3Pool contract object
    function vPool(Protocol.Info storage protocol, uint32 poolId) internal view returns (IUniswapV3Pool) {
        return protocol.pools[poolId].vPool;
    }

    /// @notice gets the wrapper address for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return VPoolWrapper contract object
    function vPoolWrapper(Protocol.Info storage protocol, uint32 poolId) internal view returns (IVPoolWrapper) {
        return protocol.pools[poolId].vPoolWrapper;
    }

    /// @notice gets the virtual twap sqrt price for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return sqrtPriceX96 virtual twap sqrt price
    function getVirtualTwapSqrtPriceX96(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        IClearingHouseStructures.Pool storage pool = protocol.pools[poolId];
        return pool.vPool.twapSqrtPrice(pool.settings.twapDuration);
    }

    /// @notice gets the virtual current sqrt price for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return sqrtPriceX96 virtual current sqrt price
    function getVirtualCurrentSqrtPriceX96(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.pools[poolId].vPool.sqrtPriceCurrent();
    }

    /// @notice gets the virtual current tick for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return tick virtual current tick
    function getVirtualCurrentTick(Protocol.Info storage protocol, uint32 poolId) internal view returns (int24 tick) {
        return protocol.pools[poolId].vPool.tickCurrent();
    }

    /// @notice gets the virtual twap price for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return priceX128 virtual twap price
    function getVirtualTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        return protocol.getVirtualTwapSqrtPriceX96(poolId).toPriceX128();
    }

    /// @notice gets the virtual current price for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return priceX128 virtual current price
    function getVirtualCurrentPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        return protocol.getVirtualCurrentSqrtPriceX96(poolId).toPriceX128();
    }

    /// @notice gets the real twap price for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return priceX128 virtual twap price
    function getRealTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        IClearingHouseStructures.Pool storage pool = protocol.pools[poolId];
        return pool.settings.oracle.getTwapPriceX128(pool.settings.twapDuration);
    }

    /// @notice gets the twap prices with deviation check for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return realPriceX128 the real price
    /// @return virtualPriceX128 the virtual price if under deviation else real price
    function getTwapPricesWithDeviationCheck(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128)
    {
        realPriceX128 = protocol.getRealTwapPriceX128(poolId);
        virtualPriceX128 = protocol.getVirtualTwapPriceX128(poolId);

        uint16 maxDeviationBps = protocol.pools[poolId].settings.maxVirtualPriceDeviationRatioBps;
        uint256 priceDeltaX128 = realPriceX128 > virtualPriceX128
            ? realPriceX128 - virtualPriceX128
            : virtualPriceX128 - realPriceX128;
        if (priceDeltaX128 > realPriceX128.mulDiv(maxDeviationBps, 1e4)) {
            // if virtual price is too off from real price then screw that, we'll just use real price
            virtualPriceX128 = realPriceX128;
        }
        return (realPriceX128, virtualPriceX128);
    }

    function getCachedVirtualTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        uint32 blockNumber = Block.number();

        PriceCache storage poolPriceCache = protocol.priceCache[poolId];
        if (poolPriceCache.updateBlockNumber == blockNumber) {
            return poolPriceCache.virtualPriceX128;
        } else {
            return protocol.getVirtualTwapPriceX128(poolId);
        }
    }

    function getCachedTwapPricesWithDeviationCheck(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128)
    {
        uint32 blockNumber = Block.number();

        PriceCache storage poolPriceCache = protocol.priceCache[poolId];
        if (poolPriceCache.updateBlockNumber == blockNumber) {
            if (poolPriceCache.isDeviationBreached) {
                return (poolPriceCache.realPriceX128, poolPriceCache.realPriceX128);
            } else {
                return (poolPriceCache.realPriceX128, poolPriceCache.virtualPriceX128);
            }
        } else {
            return protocol.getTwapPricesWithDeviationCheck(poolId);
        }
    }

    function getCachedRealTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        uint32 blockNumber = Block.number();

        PriceCache storage poolPriceCache = protocol.priceCache[poolId];
        if (poolPriceCache.updateBlockNumber == blockNumber) {
            return poolPriceCache.realPriceX128;
        } else {
            return protocol.getRealTwapPriceX128(poolId);
        }
    }

    /// @notice gets the margin ratio for a poolId
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @param isInitialMargin whether to use initial margin or maintainance margin
    /// @return margin rato in bps
    function getMarginRatioBps(
        Protocol.Info storage protocol,
        uint32 poolId,
        bool isInitialMargin
    ) internal view returns (uint16) {
        if (isInitialMargin) {
            return protocol.pools[poolId].settings.initialMarginRatioBps;
        } else {
            return protocol.pools[poolId].settings.maintainanceMarginRatioBps;
        }
    }

    /// @notice checks if the pool is cross margined
    /// @param protocol ref to the protocol state
    /// @param poolId the poolId of the pool
    /// @return bool whether the pool is cross margined
    function isPoolCrossMargined(Protocol.Info storage protocol, uint32 poolId) internal view returns (bool) {
        return protocol.pools[poolId].settings.isCrossMargined;
    }

    /// @notice Gives notional value of the given vToken and vQuote amounts
    /// @param protocol platform constants
    /// @param poolId id of the rage trade pool
    /// @param vTokenAmount amount of tokens
    /// @param vQuoteAmount amount of base
    /// @return notionalValue for the given token and vQuote amounts
    function getNotionalValue(
        Protocol.Info storage protocol,
        uint32 poolId,
        int256 vTokenAmount,
        int256 vQuoteAmount
    ) internal view returns (uint256 notionalValue) {
        return
            vTokenAmount.absUint().mulDiv(protocol.getCachedVirtualTwapPriceX128(poolId), FixedPoint128.Q128) +
            vQuoteAmount.absUint();
    }

    /// @notice Gives notional value of the given token amount
    /// @param protocol platform constants
    /// @param poolId id of the rage trade pool
    /// @param vTokenAmount amount of tokens
    /// @return notionalValue for the given token and vQuote amounts
    function getNotionalValue(
        Protocol.Info storage protocol,
        uint32 poolId,
        int256 vTokenAmount
    ) internal view returns (uint256 notionalValue) {
        return protocol.getNotionalValue(poolId, vTokenAmount, 0);
    }
}

