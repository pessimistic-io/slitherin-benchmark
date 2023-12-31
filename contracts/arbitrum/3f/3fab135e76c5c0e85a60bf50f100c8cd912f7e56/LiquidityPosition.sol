// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import { SqrtPriceMath } from "./SqrtPriceMath.sol";
import { TickMath } from "./TickMath.sol";
import { SafeCast } from "./libraries_SafeCast.sol";
import { FixedPoint96 } from "./FixedPoint96.sol";

import { FixedPoint128 } from "./FixedPoint128.sol";
import { FullMath } from "./FullMath.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";

import { PriceMath } from "./PriceMath.sol";
import { Protocol } from "./Protocol.sol";
import { SignedFullMath } from "./SignedFullMath.sol";
import { UniswapV3PoolHelper } from "./UniswapV3PoolHelper.sol";
import { FundingPayment } from "./FundingPayment.sol";

import { IClearingHouseStructures } from "./IClearingHouseStructures.sol";
import { IClearingHouseEnums } from "./IClearingHouseEnums.sol";
import { IVPoolWrapper } from "./IVPoolWrapper.sol";

/// @title Liquidity position functions
library LiquidityPosition {
    using FullMath for uint256;
    using PriceMath for uint160;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    using LiquidityPosition for LiquidityPosition.Info;
    using Protocol for Protocol.Info;

    struct Set {
        // multiple per pool because it's non-fungible, allows for 4 billion LP positions lifetime
        uint48[5] active;
        // concat(tickLow,tickHigh)
        mapping(uint48 => LiquidityPosition.Info) positions;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    struct Info {
        //Extra boolean to check if it is limit order and uint to track limit price.
        IClearingHouseEnums.LimitOrderType limitOrderType;
        // the tick range of the position;
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        int256 vTokenAmountIn;
        // funding payment checkpoints
        int256 sumALastX128;
        int256 sumBInsideLastX128;
        int256 sumFpInsideLastX128;
        // fee growth inside
        uint256 sumFeeInsideLastX128;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    error LP_AlreadyInitialized();
    error LP_IneligibleLimitOrderRemoval();

    /// @notice denotes liquidity add/remove
    /// @param accountId serial number of the account
    /// @param poolId address of token whose position was taken
    /// @param tickLower lower tick of the range updated
    /// @param tickUpper upper tick of the range updated
    /// @param liquidityDelta change in liquidity value
    /// @param limitOrderType the type of range position
    /// @param vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @param vQuoteAmountOut amount of vQuote tokens that account received (positive) or paid (negative)
    event LiquidityChanged(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        IClearingHouseEnums.LimitOrderType limitOrderType,
        int256 vTokenAmountOut,
        int256 vQuoteAmountOut,
        uint160 sqrtPriceX96
    );

    /// @param accountId serial number of the account
    /// @param poolId address of token for which funding was paid
    /// @param tickLower lower tick of the range for which funding was paid
    /// @param tickUpper upper tick of the range for which funding was paid
    /// @param amount amount of funding paid (negative) or received (positive)
    /// @param sumALastX128 val of sum of the term A in funding payment math, when op took place
    /// @param sumBInsideLastX128 val of sum of the term B in funding payment math, when op took place
    /// @param sumFpInsideLastX128 val of sum of the term Fp in funding payment math, when op took place
    /// @param sumFeeInsideLastX128 val of sum of the term Fee in wrapper, when op took place
    event LiquidityPositionFundingPaymentRealized(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int256 amount,
        int256 sumALastX128,
        int256 sumBInsideLastX128,
        int256 sumFpInsideLastX128,
        uint256 sumFeeInsideLastX128
    );

    /// @notice denotes fee payment for a range / token position
    /// @dev for a token position tickLower = tickUpper = 0
    /// @param accountId serial number of the account
    /// @param poolId address of token for which fee was paid
    /// @param tickLower lower tick of the range for which fee was paid
    /// @param tickUpper upper tick of the range for which fee was paid
    /// @param amount amount of fee paid (negative) or received (positive)
    event LiquidityPositionEarningsRealized(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int256 amount
    );

    /**
     *  Internal methods
     */

    /// @notice initializes a new LiquidityPosition.Info struct
    /// @dev Reverts if the position is already initialized
    /// @param position storage pointer of the position to initialize
    /// @param tickLower lower tick of the range
    /// @param tickUpper upper tick of the range
    function initialize(
        LiquidityPosition.Info storage position,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        if (position.isInitialized()) {
            revert LP_AlreadyInitialized();
        }

        position.tickLower = tickLower;
        position.tickUpper = tickUpper;
    }

    /// @notice changes liquidity for a position, informs pool wrapper and does necessary bookkeeping
    /// @param position storage ref of the position to update
    /// @param accountId serial number of the account, used to emit event
    /// @param poolId id of the pool for which position was updated
    /// @param liquidityDelta change in liquidity value
    /// @param balanceAdjustments memory ref to the balance adjustments struct
    /// @param protocol ref to the protocol state
    function liquidityChange(
        LiquidityPosition.Info storage position,
        uint256 accountId,
        uint32 poolId,
        int128 liquidityDelta,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        int256 vTokenPrincipal;
        int256 vQuotePrincipal;

        IVPoolWrapper wrapper = protocol.vPoolWrapper(poolId);
        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside;

        // calls wrapper to mint/burn liquidity
        if (liquidityDelta > 0) {
            uint256 vTokenPrincipal_;
            uint256 vQuotePrincipal_;
            (vTokenPrincipal_, vQuotePrincipal_, wrapperValuesInside) = wrapper.mint(
                position.tickLower,
                position.tickUpper,
                uint128(liquidityDelta)
            );
            vTokenPrincipal = vTokenPrincipal_.toInt256();
            vQuotePrincipal = vQuotePrincipal_.toInt256();
        } else {
            uint256 vTokenPrincipal_;
            uint256 vQuotePrincipal_;
            (vTokenPrincipal_, vQuotePrincipal_, wrapperValuesInside) = wrapper.burn(
                position.tickLower,
                position.tickUpper,
                uint128(-liquidityDelta)
            );
            vTokenPrincipal = -vTokenPrincipal_.toInt256();
            vQuotePrincipal = -vQuotePrincipal_.toInt256();
        }

        // calculate funding payment and liquidity fees then update checkpoints
        position.update(accountId, poolId, wrapperValuesInside, balanceAdjustments);

        // adjust in the token acounts
        balanceAdjustments.vQuoteIncrease -= vQuotePrincipal;
        balanceAdjustments.vTokenIncrease -= vTokenPrincipal;

        // emit the event
        uint160 sqrtPriceCurrent = protocol.vPool(poolId).sqrtPriceCurrent();
        emitLiquidityChangeEvent(
            position,
            accountId,
            poolId,
            liquidityDelta,
            sqrtPriceCurrent,
            -vTokenPrincipal,
            -vQuotePrincipal
        );

        // update trader position increase
        int256 vTokenAmountCurrent;
        {
            (vTokenAmountCurrent, ) = position.vTokenAmountsInRange(sqrtPriceCurrent, false);
            balanceAdjustments.traderPositionIncrease += (vTokenAmountCurrent - position.vTokenAmountIn);
        }

        uint128 liquidityNew = position.liquidity;
        if (liquidityDelta > 0) {
            liquidityNew += uint128(liquidityDelta);
        } else if (liquidityDelta < 0) {
            liquidityNew -= uint128(-liquidityDelta);
        }

        if (liquidityNew != 0) {
            // update state
            position.liquidity = liquidityNew;
            position.vTokenAmountIn = vTokenAmountCurrent + vTokenPrincipal;
        } else {
            // clear all the state
            position.liquidity = 0;
            position.vTokenAmountIn = 0;
            position.sumALastX128 = 0;
            position.sumBInsideLastX128 = 0;
            position.sumFpInsideLastX128 = 0;
            position.sumFeeInsideLastX128 = 0;
        }
    }

    /// @notice updates the position with latest checkpoints, and realises fees and fp
    /// @dev fees and funding payment are not immediately adjusted in token balance state,
    ///     balanceAdjustments struct is used to pass the necessary values to caller.
    /// @param position storage ref of the position to update
    /// @param accountId serial number of the account, used to emit event
    /// @param poolId id of the pool for which position was updated
    /// @param wrapperValuesInside range checkpoint values from the wrapper
    /// @param balanceAdjustments memory ref to the balance adjustments struct
    function update(
        LiquidityPosition.Info storage position,
        uint256 accountId,
        uint32 poolId,
        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        int256 fundingPayment = position.unrealizedFundingPayment(
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumFpInsideX128
        );
        balanceAdjustments.vQuoteIncrease += fundingPayment;

        int256 unrealizedLiquidityFee = position.unrealizedFees(wrapperValuesInside.sumFeeInsideX128).toInt256();
        balanceAdjustments.vQuoteIncrease += unrealizedLiquidityFee;

        // updating checkpoints
        position.sumALastX128 = wrapperValuesInside.sumAX128;
        position.sumBInsideLastX128 = wrapperValuesInside.sumBInsideX128;
        position.sumFpInsideLastX128 = wrapperValuesInside.sumFpInsideX128;
        position.sumFeeInsideLastX128 = wrapperValuesInside.sumFeeInsideX128;

        emit LiquidityPositionFundingPaymentRealized(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            fundingPayment,
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumBInsideX128,
            wrapperValuesInside.sumFpInsideX128,
            wrapperValuesInside.sumFeeInsideX128
        );

        emit LiquidityPositionEarningsRealized(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            unrealizedLiquidityFee
        );
    }

    /**
     *  Internal view methods
     */

    /// @notice ensures that limit order removal is valid, else reverts
    /// @param info storage ref of the position to check
    /// @param currentTick current tick in the pool
    function checkValidLimitOrderRemoval(LiquidityPosition.Info storage info, int24 currentTick) internal view {
        if (
            !((currentTick >= info.tickUpper &&
                info.limitOrderType == IClearingHouseEnums.LimitOrderType.UPPER_LIMIT) ||
                (currentTick <= info.tickLower &&
                    info.limitOrderType == IClearingHouseEnums.LimitOrderType.LOWER_LIMIT))
        ) {
            revert LP_IneligibleLimitOrderRemoval();
        }
    }

    /// @notice checks if the position is initialized
    /// @param info storage ref of the position to check
    /// @return true if the position is initialized
    function isInitialized(LiquidityPosition.Info storage info) internal view returns (bool) {
        return info.tickLower != 0 || info.tickUpper != 0;
    }

    /// @notice calculates the long side risk for the position
    /// @param position storage ref of the position to check
    /// @param valuationSqrtPriceX96 valuation sqrt price in x96
    /// @return long side risk
    function longSideRisk(LiquidityPosition.Info storage position, uint160 valuationSqrtPriceX96)
        internal
        view
        returns (uint256)
    {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);
        uint256 longPositionExecutionPriceX128;
        {
            uint160 sqrtPriceUpperMinX96 = valuationSqrtPriceX96 <= sqrtPriceUpperX96
                ? valuationSqrtPriceX96
                : sqrtPriceUpperX96;
            uint160 sqrtPriceLowerMinX96 = valuationSqrtPriceX96 <= sqrtPriceLowerX96
                ? valuationSqrtPriceX96
                : sqrtPriceLowerX96;
            longPositionExecutionPriceX128 = uint256(sqrtPriceLowerMinX96).mulDiv(sqrtPriceUpperMinX96, 1 << 64);
        }

        uint256 maxNetLongPosition;
        {
            uint256 maxLongTokens = SqrtPriceMath.getAmount0Delta(
                sqrtPriceLowerX96,
                sqrtPriceUpperX96,
                position.liquidity,
                true
            );
            //
            if (position.vTokenAmountIn >= 0) {
                //maxLongTokens in range should always be >= amount that got added to range, equality occurs when range was added at pCurrent = pHigh
                assert(maxLongTokens >= uint256(position.vTokenAmountIn));
                maxNetLongPosition = maxLongTokens - uint256(position.vTokenAmountIn);
            } else maxNetLongPosition = maxLongTokens + uint256(-1 * position.vTokenAmountIn);
        }

        return maxNetLongPosition.mulDiv(longPositionExecutionPriceX128, FixedPoint128.Q128);
    }

    /// @notice calculates the market value for the position using a provided price
    /// @param position storage ref of the position to check
    /// @param valuationSqrtPriceX96 valuation sqrt price to be used
    /// @param wrapper address of the pool wrapper
    /// @return marketValue_ the market value of the position
    function marketValue(
        LiquidityPosition.Info storage position,
        uint160 valuationSqrtPriceX96,
        IVPoolWrapper wrapper
    ) internal view returns (int256 marketValue_) {
        {
            (int256 vTokenAmount, int256 vQuoteAmount) = position.vTokenAmountsInRange(valuationSqrtPriceX96, false);
            uint256 priceX128 = valuationSqrtPriceX96.toPriceX128();
            marketValue_ = vTokenAmount.mulDiv(priceX128, FixedPoint128.Q128) + vQuoteAmount;
        }
        // adding fees
        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside = wrapper.getExtrapolatedValuesInside(
            position.tickLower,
            position.tickUpper
        );
        marketValue_ += position.unrealizedFees(wrapperValuesInside.sumFeeInsideX128).toInt256();
        marketValue_ += position.unrealizedFundingPayment(
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumFpInsideX128
        );
    }

    /// @notice calculates the max net position for the position
    /// @param position storage ref of the position to check
    /// @return maxNetPosition the max net position of the position
    function maxNetPosition(LiquidityPosition.Info storage position) internal view returns (uint256) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        if (position.vTokenAmountIn >= 0)
            return
                SqrtPriceMath.getAmount0Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, position.liquidity, true) -
                uint256(position.vTokenAmountIn);
        else
            return
                SqrtPriceMath.getAmount0Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, position.liquidity, true) +
                uint256(-1 * position.vTokenAmountIn);
    }

    /// @notice calculates the current net position for the position
    /// @param position storage ref of the position to check
    /// @param sqrtPriceCurrent the current sqrt price, used to calculate net position
    /// @return netTokenPosition the current net position of the position
    function netPosition(LiquidityPosition.Info storage position, uint160 sqrtPriceCurrent)
        internal
        view
        returns (int256 netTokenPosition)
    {
        int256 vTokenAmountCurrent;
        (vTokenAmountCurrent, ) = position.vTokenAmountsInRange(sqrtPriceCurrent, false);
        netTokenPosition = (vTokenAmountCurrent - position.vTokenAmountIn);
    }

    /// @notice calculates the current virtual token amounts for the position
    /// @param position storage ref of the position to check
    /// @param sqrtPriceCurrent the current sqrt price, used to calculate virtual token amounts
    /// @param roundUp whether to round up the token amounts, purpose to charge user more and give less
    /// @return vTokenAmount the current vToken amount
    /// @return vQuoteAmount the current vQuote amount
    function vTokenAmountsInRange(
        LiquidityPosition.Info storage position,
        uint160 sqrtPriceCurrent,
        bool roundUp
    ) internal view returns (int256 vTokenAmount, int256 vQuoteAmount) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        // If price is outside the range, then consider it at the ends
        // for calculation of amounts
        uint160 sqrtPriceMiddleX96 = sqrtPriceCurrent;
        if (sqrtPriceCurrent < sqrtPriceLowerX96) {
            sqrtPriceMiddleX96 = sqrtPriceLowerX96;
        } else if (sqrtPriceCurrent > sqrtPriceUpperX96) {
            sqrtPriceMiddleX96 = sqrtPriceUpperX96;
        }

        vTokenAmount = SqrtPriceMath
            .getAmount0Delta(sqrtPriceMiddleX96, sqrtPriceUpperX96, position.liquidity, roundUp)
            .toInt256();
        vQuoteAmount = SqrtPriceMath
            .getAmount1Delta(sqrtPriceLowerX96, sqrtPriceMiddleX96, position.liquidity, roundUp)
            .toInt256();
    }

    /// @notice returns vQuoteIncrease due to unrealised funding payment for the liquidity position (+ve means receiving and -ve means giving)
    /// @param position storage ref of the position to check
    /// @param sumAX128 the sumA value from the pool wrapper
    /// @param sumFpInsideX128 the sumFp in the position's range from the pool wrapper
    /// @return vQuoteIncrease the amount of vQuote that should be added to the account's vQuote balance
    function unrealizedFundingPayment(
        LiquidityPosition.Info storage position,
        int256 sumAX128,
        int256 sumFpInsideX128
    ) internal view returns (int256 vQuoteIncrease) {
        // subtract the bill from the account's vQuote balance
        vQuoteIncrease = -FundingPayment.bill(
            sumAX128,
            sumFpInsideX128,
            position.sumALastX128,
            position.sumBInsideLastX128,
            position.sumFpInsideLastX128,
            position.liquidity
        );
    }

    /// @notice calculates the unrealised lp fees for the position
    /// @param position storage ref of the position to check
    /// @param sumFeeInsideX128 the global sumFee in the position's range from the pool wrapper
    /// @return vQuoteIncrease the amount of vQuote that should be added to the account's vQuote balance
    function unrealizedFees(LiquidityPosition.Info storage position, uint256 sumFeeInsideX128)
        internal
        view
        returns (uint256 vQuoteIncrease)
    {
        vQuoteIncrease = (sumFeeInsideX128 - position.sumFeeInsideLastX128).mulDiv(
            position.liquidity,
            FixedPoint128.Q128
        );
    }

    function emitLiquidityChangeEvent(
        LiquidityPosition.Info storage position,
        uint256 accountId,
        uint32 poolId,
        int128 liquidityDelta,
        uint160 sqrtPriceX96,
        int256 vTokenAmountOut,
        int256 vQuoteAmountOut
    ) internal {
        emit LiquidityChanged(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            liquidityDelta,
            position.limitOrderType,
            vTokenAmountOut,
            vQuoteAmountOut,
            sqrtPriceX96
        );
    }
}

