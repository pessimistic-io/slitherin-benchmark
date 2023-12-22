// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import { TickMath } from "./TickMath.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { PoolAddress } from "./PoolAddress.sol";
import { BitMath } from "./BitMath.sol";
import { SwapMath } from "./SwapMath.sol";
import { FullMath } from "./FullMath.sol";
import { LiquidityMath } from "./LiquidityMath.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import { PerpMath } from "./PerpMath.sol";

/**
 * Uniswap's v3 pool: token0 & token1
 * -> token0's price = token1 / token0; tick index = log(1.0001, token0's price)
 * Our system: base & quote
 * -> base's price = quote / base; tick index = log(1.0001, base price)
 * Thus, we require that (base, quote) = (token0, token1) is always true for convenience
 */
library UniswapV3Broker {
    using SafeMathUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using PerpMath for int128;
    using PerpMath for uint160;
    using PerpMath for int256;
    using PerpMath for uint256;
    using PerpSafeCast for uint256;
    using PerpSafeCast for int256;

    //
    // STRUCT
    //

    struct AddLiquidityParams {
        address baseToken;
        uint128 liquidity;
    }

    struct InternalAddLiquidityParams {
        address pool;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        bytes data;
    }

    struct AddLiquidityResponse {
        uint256 base;
        uint256 quote;
        uint128 liquidity;
    }

    struct RemoveLiquidityParams {
        address baseToken;
        uint128 liquidity;
    }

    struct InternalRemoveLiquidityParams {
        address pool;
        address recipient;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
    }

    /// @param base amount of base token received from burning the liquidity (excl. fee)
    /// @param quote amount of quote token received from burning the liquidity (excl. fee)
    struct RemoveLiquidityResponse {
        uint256 base;
        uint256 quote;
    }

    struct SwapState {
        int24 tick;
        uint160 sqrtPriceX96;
        int256 amountSpecifiedRemaining;
        uint128 liquidity;
    }

    struct SwapParams {
        address pool;
        address recipient;
        bool isBaseToQuote;
        bool isExactInput;
        uint256 amount;
        uint160 sqrtPriceLimitX96;
        bytes data;
    }

    struct SwapResponse {
        uint256 base;
        uint256 quote;
    }

    struct ReplaySwapParams {
        address baseToken;
        bool isBaseToQuote;
        bool shouldUpdateState;
        int256 amount;
        uint160 sqrtPriceLimitX96;
        uint24 uniswapFeeRatio;
    }

    struct ReplaySwapResponse {
        int24 tick;
        uint256 fee;
        uint256 amountIn;
        uint256 amountOut;
    }

    struct InternalSwapStep {
        uint160 initialSqrtPriceX96;
        int24 nextTick;
        bool isNextTickInitialized;
        uint160 nextSqrtPriceX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 fee;
    }

    //
    // CONSTANT
    //

    uint256 internal constant _DUST = 10;

    //
    // INTERNAL NON-VIEW
    //

    struct MintCallbackData {
        address pool;
    }

    function addLiquidity(
        address pool,
        AddLiquidityParams calldata params
    ) external returns (AddLiquidityResponse memory) {
        (int24 lowerTick, int24 upperTick) = getFullTickForLiquidity(pool);
        // add liquidity to pool
        return
            _addLiquidity(
                InternalAddLiquidityParams(
                    pool,
                    lowerTick,
                    upperTick,
                    params.liquidity,
                    abi.encode(MintCallbackData(pool))
                )
            );
    }

    function _addLiquidity(InternalAddLiquidityParams memory params) internal returns (AddLiquidityResponse memory) {
        (uint256 addedAmount0, uint256 addedAmount1) = IUniswapV3Pool(params.pool).mint(
            address(this),
            params.lowerTick,
            params.upperTick,
            params.liquidity,
            params.data
        );
        return AddLiquidityResponse({ base: addedAmount0, quote: addedAmount1, liquidity: params.liquidity });
    }

    function removeLiquidity(
        address pool,
        address recipient, // _clearingHouse
        RemoveLiquidityParams calldata params
    ) external returns (RemoveLiquidityResponse memory) {
        (int24 lowerTick, int24 upperTick) = getFullTickForLiquidity(pool);
        // adremoved liquidity from pool
        return _removeLiquidity(InternalRemoveLiquidityParams(pool, recipient, lowerTick, upperTick, params.liquidity));
    }

    function _removeLiquidity(
        InternalRemoveLiquidityParams memory params
    ) internal returns (RemoveLiquidityResponse memory) {
        // call burn(), which only updates tokensOwed instead of transferring the tokens
        (uint256 amount0Burned, uint256 amount1Burned) = IUniswapV3Pool(params.pool).burn(
            params.lowerTick,
            params.upperTick,
            params.liquidity
        );

        // call collect() to transfer tokens to CH
        // we don't care about the returned values here as they include:
        // 1. every maker's fee in the same range (ClearingHouse is the only maker in the pool's perspective)
        // 2. the amount of token equivalent to liquidity burned
        IUniswapV3Pool(params.pool).collect(
            params.recipient,
            params.lowerTick,
            params.upperTick,
            type(uint128).max,
            type(uint128).max
        );

        return RemoveLiquidityResponse({ base: amount0Burned, quote: amount1Burned });
    }

    function swap(SwapParams memory params) external returns (SwapResponse memory response) {
        // UniswapV3Pool uses the sign to determine isExactInput or not
        int256 specifiedAmount = params.isExactInput ? params.amount.toInt256() : params.amount.neg256();

        // signedAmount0 & signedAmount1 are delta amounts, in the perspective of the pool
        // > 0: pool gets; user pays
        // < 0: pool provides; user gets
        (int256 signedAmount0, int256 signedAmount1) = IUniswapV3Pool(params.pool).swap(
            params.recipient,
            params.isBaseToQuote,
            specifiedAmount,
            params.sqrtPriceLimitX96 == 0
                ? (params.isBaseToQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96,
            params.data
        );

        (uint256 amount0, uint256 amount1) = (signedAmount0.abs(), signedAmount1.abs());

        // isExactInput = true, isZeroForOne = true => exact token0
        // isExactInput = false, isZeroForOne = false => exact token0
        // isExactInput = false, isZeroForOne = true => exact token1
        // isExactInput = true, isZeroForOne = false => exact token1
        uint256 exactAmount = params.isExactInput == params.isBaseToQuote ? amount0 : amount1;

        // if no price limit, require the full output amount as it's technically possible for amounts to not match
        // UB_UOA: unmatched output amount
        if (!params.isExactInput && params.sqrtPriceLimitX96 == 0) {
            require(
                (exactAmount > params.amount ? exactAmount.sub(params.amount) : params.amount.sub(exactAmount)) < _DUST,
                "UB_UOA"
            );
            return params.isBaseToQuote ? SwapResponse(amount0, params.amount) : SwapResponse(params.amount, amount1);
        }

        return SwapResponse(amount0, amount1);
    }

    //
    // INTERNAL VIEW
    //

    function getPool(
        address factory,
        address quoteToken,
        address baseToken,
        uint24 uniswapFeeRatio
    ) external view returns (address) {
        PoolAddress.PoolKey memory poolKeys = PoolAddress.getPoolKey(quoteToken, baseToken, uniswapFeeRatio);
        return IUniswapV3Factory(factory).getPool(poolKeys.token0, poolKeys.token1, uniswapFeeRatio);
    }

    function getTickSpacing(address pool) public view returns (int24 tickSpacing) {
        tickSpacing = IUniswapV3Pool(pool).tickSpacing();
    }

    function getSlot0(
        address pool
    )
        public
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return IUniswapV3Pool(pool).slot0();
    }

    function getTick(address pool) external view returns (int24 tick) {
        (, tick, , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    function getIsTickInitialized(address pool, int24 tick) external view returns (bool initialized) {
        (, , , , , , , initialized) = IUniswapV3Pool(pool).ticks(tick);
    }

    function getTickLiquidityNet(address pool, int24 tick) public view returns (int128 liquidityNet) {
        (, liquidityNet, , , , , , ) = IUniswapV3Pool(pool).ticks(tick);
    }

    function getSqrtMarkPriceX96(address pool) external view returns (uint160 sqrtMarkPrice) {
        (sqrtMarkPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    function getLiquidity(address pool) external view returns (uint128 liquidity) {
        return IUniswapV3Pool(pool).liquidity();
    }

    /// @dev if twapInterval < 10 (should be less than 1 block), return mark price without twap directly,
    ///      as twapInterval is too short and makes getting twap over such a short period meaningless
    function getSqrtMarkTwapX96(address pool, uint32 twapInterval) external view returns (uint160) {
        return getSqrtMarkTwapX96From(pool, 0, twapInterval);
    }

    function getSqrtMarkTwapX96From(
        address pool,
        uint32 secondsAgo,
        uint32 twapInterval
    ) public view returns (uint160) {
        // return the current price as twapInterval is too short/ meaningless
        if (twapInterval < 10) {
            (uint160 sqrtMarkPrice, , , , , , ) = getSlot0(pool);
            return sqrtMarkPrice;
        }
        uint32[] memory secondsAgos = new uint32[](2);

        // solhint-disable-next-line not-rely-on-time
        secondsAgos[0] = secondsAgo + twapInterval;
        secondsAgos[1] = secondsAgo;
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);

        // tick(imprecise as it's an integer) to price
        return TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / twapInterval));
    }

    // copied from UniswapV3-core
    /// @param isBaseToQuote originally lte, meaning that the next tick < the current tick
    function getNextInitializedTickWithinOneWord(
        address pool,
        int24 tick,
        int24 tickSpacing,
        bool isBaseToQuote
    ) public view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

        if (isBaseToQuote) {
            (int16 wordPos, uint8 bitPos) = _getPositionOfInitializedTickWithinOneWord(compressed);
            // all the 1s at or to the right of the current bitPos
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = _getTickBitmap(pool, wordPos) & mask;

            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                : (compressed - int24(bitPos)) * tickSpacing;
        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            (int16 wordPos, uint8 bitPos) = _getPositionOfInitializedTickWithinOneWord(compressed + 1);
            // all the 1s at or to the left of the bitPos
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = _getTickBitmap(pool, wordPos) & mask;

            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        }
    }

    function getSwapState(
        address pool,
        int256 signedScaledAmountForReplaySwap
    ) public view returns (SwapState memory) {
        (uint160 sqrtMarkPrice, int24 tick, , , , , ) = getSlot0(pool);
        uint128 liquidity = IUniswapV3Pool(pool).liquidity();
        return
            SwapState({
                tick: tick,
                sqrtPriceX96: sqrtMarkPrice,
                amountSpecifiedRemaining: signedScaledAmountForReplaySwap,
                liquidity: liquidity
            });
    }

    //
    // PRIVATE VIEW
    //

    function _getTickBitmap(address pool, int16 wordPos) private view returns (uint256 tickBitmap) {
        return IUniswapV3Pool(pool).tickBitmap(wordPos);
    }

    /// @dev this function is Uniswap's TickBitmap.position()
    function _getPositionOfInitializedTickWithinOneWord(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(tick % 256);
    }

    function getFullTickForLiquidity(address pool) public view returns (int24 lowerTick, int24 upperTick) {
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();
        lowerTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        upperTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
    }

    function replaySwap(
        address pool,
        ReplaySwapParams memory params
    ) external view returns (ReplaySwapResponse memory) {
        // address pool = IMarketRegistry(marketRegistry).getPool(params.baseToken);
        bool isExactInput = params.amount > 0;
        uint256 fee;

        SwapState memory swapState = getSwapState(pool, params.amount);

        params.sqrtPriceLimitX96 = params.sqrtPriceLimitX96 == 0
            ? (params.isBaseToQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
            : params.sqrtPriceLimitX96;

        // if there is residue in amountSpecifiedRemaining, makers can get a tiny little bit less than expected,
        // which is safer for the system
        int24 tickSpacing = getTickSpacing(pool);

        while (swapState.amountSpecifiedRemaining != 0 && swapState.sqrtPriceX96 != params.sqrtPriceLimitX96) {
            InternalSwapStep memory step;
            step.initialSqrtPriceX96 = swapState.sqrtPriceX96;

            // find next tick
            // note the search is bounded in one word
            (step.nextTick, step.isNextTickInitialized) = getNextInitializedTickWithinOneWord(
                pool,
                swapState.tick,
                tickSpacing,
                params.isBaseToQuote
            );

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.nextTick < TickMath.MIN_TICK) {
                step.nextTick = TickMath.MIN_TICK;
            } else if (step.nextTick > TickMath.MAX_TICK) {
                step.nextTick = TickMath.MAX_TICK;
            }

            // get the next price of this step (either next tick's price or the ending price)
            // use sqrtPrice instead of tick is more precise
            step.nextSqrtPriceX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            // find the next swap checkpoint
            // (either reached the next price of this step, or exhausted remaining amount specified)
            (swapState.sqrtPriceX96, step.amountIn, step.amountOut, step.fee) = SwapMath.computeSwapStep(
                swapState.sqrtPriceX96,
                (
                    params.isBaseToQuote
                        ? step.nextSqrtPriceX96 < params.sqrtPriceLimitX96
                        : step.nextSqrtPriceX96 > params.sqrtPriceLimitX96
                )
                    ? params.sqrtPriceLimitX96
                    : step.nextSqrtPriceX96,
                swapState.liquidity,
                swapState.amountSpecifiedRemaining,
                // isBaseToQuote: fee is charged in base token in uniswap pool; thus, use uniswapFeeRatio to replay
                // !isBaseToQuote: fee is charged in quote token in clearing house; thus, use exchangeFeeRatioRatio
                params.isBaseToQuote ? params.uniswapFeeRatio : 0
            );

            // user input 1 quote:
            // quote token to uniswap ===> 1*0.98/0.99 = 0.98989899
            // fee = 0.98989899 * 2% = 0.01979798
            if (isExactInput) {
                swapState.amountSpecifiedRemaining = swapState.amountSpecifiedRemaining.sub(
                    step.amountIn.add(step.fee).toInt256()
                );
            } else {
                swapState.amountSpecifiedRemaining = swapState.amountSpecifiedRemaining.add(step.amountOut.toInt256());
            }

            // update CH's global fee growth if there is liquidity in this range
            // note CH only collects quote fee when swapping base -> quote
            if (swapState.liquidity > 0) {
                if (params.isBaseToQuote) {
                    step.fee = FullMath.mulDivRoundingUp(step.amountOut, 0, 1e6);
                }
                fee += step.fee;
            }

            if (swapState.sqrtPriceX96 == step.nextSqrtPriceX96) {
                // we have reached the tick's boundary
                if (step.isNextTickInitialized) {
                    if (params.shouldUpdateState) {}
                    int128 liquidityNet = getTickLiquidityNet(pool, step.nextTick);
                    if (params.isBaseToQuote) liquidityNet = liquidityNet.neg128();
                    swapState.liquidity = LiquidityMath.addDelta(swapState.liquidity, liquidityNet);
                }

                swapState.tick = params.isBaseToQuote ? step.nextTick - 1 : step.nextTick;
            } else if (swapState.sqrtPriceX96 != step.initialSqrtPriceX96) {
                // update state.tick corresponding to the current price if the price has changed in this step
                swapState.tick = TickMath.getTickAtSqrtRatio(swapState.sqrtPriceX96);
            }
        }

        return ReplaySwapResponse({ tick: swapState.tick, fee: fee, amountIn: 0, amountOut: 0 });
    }

    function estimateSwap(
        address pool,
        ReplaySwapParams memory params
    ) public view returns (ReplaySwapResponse memory) {
        bool isExactInput = params.amount > 0;
        uint256 fee;

        uint256 amountIn;
        uint256 amountOut;

        SwapState memory swapState = getSwapState(pool, params.amount);

        params.sqrtPriceLimitX96 = params.sqrtPriceLimitX96 == 0
            ? (params.isBaseToQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
            : params.sqrtPriceLimitX96;

        // if there is residue in amountSpecifiedRemaining, makers can get a tiny little bit less than expected,
        // which is safer for the system
        int24 tickSpacing = getTickSpacing(pool);

        while (swapState.amountSpecifiedRemaining != 0 && swapState.sqrtPriceX96 != params.sqrtPriceLimitX96) {
            InternalSwapStep memory step;
            step.initialSqrtPriceX96 = swapState.sqrtPriceX96;

            // find next tick
            // note the search is bounded in one word
            (step.nextTick, step.isNextTickInitialized) = getNextInitializedTickWithinOneWord(
                pool,
                swapState.tick,
                tickSpacing,
                params.isBaseToQuote
            );

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.nextTick < TickMath.MIN_TICK) {
                step.nextTick = TickMath.MIN_TICK;
            } else if (step.nextTick > TickMath.MAX_TICK) {
                step.nextTick = TickMath.MAX_TICK;
            }

            // get the next price of this step (either next tick's price or the ending price)
            // use sqrtPrice instead of tick is more precise
            step.nextSqrtPriceX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            // find the next swap checkpoint
            // (either reached the next price of this step, or exhausted remaining amount specified)
            (swapState.sqrtPriceX96, step.amountIn, step.amountOut, step.fee) = SwapMath.computeSwapStep(
                swapState.sqrtPriceX96,
                (
                    params.isBaseToQuote
                        ? step.nextSqrtPriceX96 < params.sqrtPriceLimitX96
                        : step.nextSqrtPriceX96 > params.sqrtPriceLimitX96
                )
                    ? params.sqrtPriceLimitX96
                    : step.nextSqrtPriceX96,
                swapState.liquidity,
                swapState.amountSpecifiedRemaining,
                // isBaseToQuote: fee is charged in base token in uniswap pool; thus, use uniswapFeeRatio to replay
                // !isBaseToQuote: fee is charged in quote token in clearing house; thus, use exchangeFeeRatioRatio
                params.isBaseToQuote ? params.uniswapFeeRatio : 0
            );

            // user input 1 quote:
            // quote token to uniswap ===> 1*0.98/0.99 = 0.98989899
            // fee = 0.98989899 * 2% = 0.01979798
            if (isExactInput) {
                swapState.amountSpecifiedRemaining = swapState.amountSpecifiedRemaining.sub(
                    step.amountIn.add(step.fee).toInt256()
                );
            } else {
                swapState.amountSpecifiedRemaining = swapState.amountSpecifiedRemaining.add(step.amountOut.toInt256());
            }
            amountIn = amountIn.add(step.amountIn);
            amountOut = amountOut.add(step.amountOut);
            // update CH's global fee growth if there is liquidity in this range
            // note CH only collects quote fee when swapping base -> quote
            if (swapState.liquidity > 0) {
                if (params.isBaseToQuote) {
                    step.fee = FullMath.mulDivRoundingUp(step.amountOut, 0, 1e6);
                }
                fee += step.fee;
            }

            if (swapState.sqrtPriceX96 == step.nextSqrtPriceX96) {
                // we have reached the tick's boundary
                if (step.isNextTickInitialized) {
                    if (params.shouldUpdateState) {}
                    int128 liquidityNet = getTickLiquidityNet(pool, step.nextTick);
                    if (params.isBaseToQuote) liquidityNet = liquidityNet.neg128();
                    swapState.liquidity = LiquidityMath.addDelta(swapState.liquidity, liquidityNet);
                }

                swapState.tick = params.isBaseToQuote ? step.nextTick - 1 : step.nextTick;
            } else if (swapState.sqrtPriceX96 != step.initialSqrtPriceX96) {
                // update state.tick corresponding to the current price if the price has changed in this step
                swapState.tick = TickMath.getTickAtSqrtRatio(swapState.sqrtPriceX96);
            }
        }

        return ReplaySwapResponse({ tick: swapState.tick, fee: fee, amountIn: amountIn, amountOut: amountOut });
    }
}

