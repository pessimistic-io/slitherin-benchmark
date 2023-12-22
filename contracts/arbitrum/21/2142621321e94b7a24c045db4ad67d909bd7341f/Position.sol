// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <0.8.0;
pragma abicoder v2;

import "./FullMath.sol";
import "./FixedPoint128.sol";
import "./LiquidityMath.sol";
import "./SqrtPriceMath.sol";
import "./States.sol";
import "./Tick.sol";
import "./TickMath.sol";
import "./TickBitmap.sol";
import "./Oracle.sol";

import "./IVotingEscrow.sol";
import "./IVoter.sol";

/// @title Position
/// @notice Positions represent an owner address' liquidity between a lower and upper tick boundary
/// @dev Positions store additional state for tracking fees owed to the position
library Position {
    /// @notice Returns the hash used to store positions in a mapping
    /// @param owner The address of the position owner
    /// @param index The index of the position
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return _hash The hash used to store positions in a mapping
    function positionHash(
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, index, tickLower, tickUpper));
    }

    /// @notice Returns the Info struct of a position, given an owner and position boundaries
    /// @param self The mapping containing all user positions
    /// @param owner The address of the position owner
    /// @param index The index of the position
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return position The position info struct of the given owners' position
    function get(
        mapping(bytes32 => PositionInfo) storage self,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (PositionInfo storage position) {
        position = self[positionHash(owner, index, tickLower, tickUpper)];
    }

    /// @notice Returns the BoostInfo struct of a position, given an owner, index, and position boundaries
    /// @param self The mapping containing all user boosted positions within the period
    /// @param owner The address of the position owner
    /// @param index The index of the position
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return position The position BoostInfo struct of the given owners' position within the period
    function get(
        PeriodBoostInfo storage self,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (BoostInfo storage position) {
        position = self.positions[positionHash(owner, index, tickLower, tickUpper)];
    }

    /// @notice Credits accumulated fees to a user's position
    /// @param self The individual position to update
    /// @param liquidityDelta The change in pool liquidity as a result of the position update
    /// @param feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
    /// @param feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
    function update(
        PositionInfo storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        PositionInfo memory _self = self;

        uint128 liquidityNext;
        if (liquidityDelta == 0) {
            require(_self.liquidity > 0, 'NP'); // disallow pokes for 0 liquidity positions
            liquidityNext = _self.liquidity;
        } else {
            liquidityNext = LiquidityMath.addDelta(_self.liquidity, liquidityDelta);
        }

        // calculate accumulated fees
        uint128 tokensOwed0 = uint128(
            FullMath.mulDiv(feeGrowthInside0X128 - _self.feeGrowthInside0LastX128, _self.liquidity, FixedPoint128.Q128)
        );
        uint128 tokensOwed1 = uint128(
            FullMath.mulDiv(feeGrowthInside1X128 - _self.feeGrowthInside1LastX128, _self.liquidity, FixedPoint128.Q128)
        );

        // update the position
        if (liquidityDelta != 0) {
            self.liquidity = liquidityNext;
        }
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            // overflow is acceptable, have to withdraw before you hit type(uint128).max fees
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }

    /// @notice Updates boosted balances to a user's position
    /// @param self The individual boosted position to update
    /// @param boostedLiquidityDelta The change in pool liquidity as a result of the position update
    /// @param secondsPerBoostedLiquidityPeriodX128 The seconds in range gained per unit of liquidity, inside the position's tick boundaries for this period
    function update(
        BoostInfo storage self,
        int128 boostedLiquidityDelta,
        uint256 secondsPerBoostedLiquidityPeriodX128
    ) internal {
        self.boostAmount = LiquidityMath.addDelta(self.boostAmount, boostedLiquidityDelta);
        int256 boostedSecondsDebtDeltax128 = boostedLiquidityDelta > 0
            ? int256(
                FullMath.mulDiv(
                    uint256(boostedLiquidityDelta),
                    secondsPerBoostedLiquidityPeriodX128,
                    FixedPoint128.Q128
                )
            )
            : int256(
                -FullMath.mulDiv(
                    uint256(-boostedLiquidityDelta),
                    secondsPerBoostedLiquidityPeriodX128,
                    FixedPoint128.Q128
                )
            );

        self.boostedSecondsDebtx128 = boostedLiquidityDelta > 0
            ? int160(self.boostedSecondsDebtx128 + boostedSecondsDebtDeltax128)
            : int160(self.boostedSecondsDebtx128 - boostedSecondsDebtDeltax128); // can't overflow since each period is way less than uint31
    }

    struct ModifyPositionParams {
        // the address that owns the position
        address owner;
        uint256 index;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        int128 liquidityDelta;
        uint256 veRamTokenId;
    }

    /// @dev Effect some changes to a position
    /// @param params the position details and the change to the position's liquidity to effect
    /// @return position a storage pointer referencing the position with the given owner and tick range
    /// @return amount0 the amount of token0 owed to the pool, negative if the pool should pay the recipient
    /// @return amount1 the amount of token1 owed to the pool, negative if the pool should pay the recipient
    function _modifyPosition(
        ModifyPositionParams memory params
    ) external returns (PositionInfo storage position, int256 amount0, int256 amount1) {
        States.PoolStates storage states = States.getStorage();

        // check ticks
        require(params.tickLower < params.tickUpper, 'TLU');
        require(params.tickLower >= TickMath.MIN_TICK, 'TLM');
        require(params.tickUpper <= TickMath.MAX_TICK, 'TUM');

        Slot0 memory _slot0 = states.slot0; // SLOAD for gas optimization

        int128 boostedLiquidityDelta;
        (position, boostedLiquidityDelta) = _updatePosition(
            UpdatePositionParams({
                owner: params.owner,
                index: params.index,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta,
                tick: _slot0.tick,
                veRamTokenId: params.veRamTokenId
            })
        );

        if (params.liquidityDelta != 0 || boostedLiquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                // current tick is inside the passed range
                uint128 liquidityBefore = states.liquidity; // SLOAD for gas optimization
                uint128 boostedLiquidityBefore = states.boostedLiquidity;

                // write an oracle entry
                (states.slot0.observationIndex, states.slot0.observationCardinality) = Oracle.write(
                    states.observations,
                    _slot0.observationIndex,
                    States._blockTimestamp(),
                    _slot0.tick,
                    liquidityBefore,
                    boostedLiquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );

                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );

                states.liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
                states.boostedLiquidity = LiquidityMath.addDelta(boostedLiquidityBefore, boostedLiquidityDelta);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    struct UpdatePositionParams {
        // the owner of the position
        address owner;
        // the index of the position
        uint256 index;
        // the lower tick of the position's tick range
        int24 tickLower;
        // the upper tick of the position's tick range
        int24 tickUpper;
        // the amount liquidity changes by
        int128 liquidityDelta;
        // the current tick, passed to avoid sloads
        int24 tick;
        // the veRamTokenId to be attached
        uint256 veRamTokenId;
    }

    struct UpdatePositionCache {
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        bool flippedUpper;
        bool flippedLower;
    }

    struct ObservationCache {
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        uint160 secondsPerBoostedLiquidityPeriodX128;
    }

    /// @dev Gets and updates a position with the given liquidity delta
    /// @param params the position details and the change to the position's liquidity to effect
    function _updatePosition(
        UpdatePositionParams memory params
    ) private returns (PositionInfo storage position, int128 boostedLiquidityDelta) {
        States.PoolStates storage states = States.getStorage();

        uint256 period = States._blockTimestamp() / 1 weeks;
        position = get(states.positions, params.owner, params.index, params.tickLower, params.tickUpper);
        BoostInfo storage boostedPosition = get(
            states.boostInfos[period],
            params.owner,
            params.index,
            params.tickLower,
            params.tickUpper
        );

        {
            // this is needed to determine attachment and newBoostedLiquidity
            uint128 newLiquidity = LiquidityMath.addDelta(position.liquidity, params.liquidityDelta);

            // detach if new liquidity is 0
            if (newLiquidity == 0) {
                _switchAttached(position, boostedPosition, 0);
                params.veRamTokenId = 0;
            }

            if (params.veRamTokenId != 0) {
                _switchAttached(position, boostedPosition, params.veRamTokenId);
            }

            {
                uint256 oldBoostedLiquidity = boostedPosition.boostAmount;
                uint256 newBoostedLiquidity = LiquidityMath.calculateBoostedLiquidity(
                    newLiquidity,
                    (boostedPosition.veRamAmount),
                    states.boostInfos[period].totalVeRamAmount
                );
                boostedLiquidityDelta = int128(newBoostedLiquidity - oldBoostedLiquidity);
            }
        }

        UpdatePositionCache memory cache;

        cache.feeGrowthGlobal0X128 = states.feeGrowthGlobal0X128; // SLOAD for gas optimization
        cache.feeGrowthGlobal1X128 = states.feeGrowthGlobal1X128; // SLOAD for gas optimization

        // if we need to update the ticks, do it
        if (params.liquidityDelta != 0 || boostedLiquidityDelta != 0) {
            uint32 time = States._blockTimestamp();
            ObservationCache memory observationCache;
            (
                observationCache.tickCumulative,
                observationCache.secondsPerLiquidityCumulativeX128,
                observationCache.secondsPerBoostedLiquidityPeriodX128
            ) = Oracle.observeSingle(
                states.observations,
                time,
                0,
                states.slot0.tick,
                states.slot0.observationIndex,
                states.liquidity,
                states.boostedLiquidity,
                states.slot0.observationCardinality
            );

            cache.flippedLower = Tick.update(
                states._ticks,
                Tick.UpdateTickParams(
                    params.tickLower,
                    params.tick,
                    params.liquidityDelta,
                    boostedLiquidityDelta,
                    cache.feeGrowthGlobal0X128,
                    cache.feeGrowthGlobal1X128,
                    observationCache.secondsPerLiquidityCumulativeX128,
                    observationCache.secondsPerBoostedLiquidityPeriodX128,
                    observationCache.tickCumulative,
                    time,
                    false,
                    states.maxLiquidityPerTick
                )
            );
            cache.flippedUpper = Tick.update(
                states._ticks,
                Tick.UpdateTickParams(
                    params.tickUpper,
                    params.tick,
                    params.liquidityDelta,
                    boostedLiquidityDelta,
                    cache.feeGrowthGlobal0X128,
                    cache.feeGrowthGlobal1X128,
                    observationCache.secondsPerLiquidityCumulativeX128,
                    observationCache.secondsPerBoostedLiquidityPeriodX128,
                    observationCache.tickCumulative,
                    time,
                    true,
                    states.maxLiquidityPerTick
                )
            );

            if (cache.flippedLower) {
                TickBitmap.flipTick(states.tickBitmap, params.tickLower, states.tickSpacing);
            }
            if (cache.flippedUpper) {
                TickBitmap.flipTick(states.tickBitmap, params.tickUpper, states.tickSpacing);
            }
        }

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = Tick.getFeeGrowthInside(
            states._ticks,
            params.tickLower,
            params.tickUpper,
            params.tick,
            cache.feeGrowthGlobal0X128,
            cache.feeGrowthGlobal1X128
        );

        update(position, params.liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        // update boostedLiquidity if needed
        if (boostedLiquidityDelta != 0) {
            Slot0 memory _slot0 = states.slot0;

            (, , uint160 secondsPerBoostedLiquidityPeriodX128) = Oracle.observeSingle(
                states.observations,
                States._blockTimestamp(),
                0,
                _slot0.tick,
                _slot0.observationIndex,
                states.liquidity,
                states.boostedLiquidity,
                _slot0.observationCardinality
            );

            update(boostedPosition, boostedLiquidityDelta, secondsPerBoostedLiquidityPeriodX128);
        }

        // clear any tick data that is no longer needed
        if (params.liquidityDelta < 0) {
            if (cache.flippedLower) {
                Tick.clear(states._ticks, params.tickLower);
            }
            if (cache.flippedUpper) {
                Tick.clear(states._ticks, params.tickUpper);
            }
        }
    }

    /// @notice updates attached veRam tokenId and veRam amount
    /// @dev can only be called in _updatePostion since boostedSecondsDebt needs to be updated when this is called
    /// @param position the user's position
    /// @param boostedPosition the user's boosted position
    /// @param veRamTokenId the veRam tokenId to switch to
    function _switchAttached(
        PositionInfo storage position,
        BoostInfo storage boostedPosition,
        uint256 veRamTokenId
    ) private {
        States.PoolStates storage states = States.getStorage();
        address _veRam = states.veRam;

        require(
            veRamTokenId == 0 ||
                msg.sender == states.nfpManager ||
                msg.sender == IVotingEscrow(_veRam).ownerOf(veRamTokenId),
            'TNA' // tokenId not authorized
        );
        uint256 oldAttached = position.attachedVeRamId;

        // call detach and attach if needed
        if (veRamTokenId != oldAttached) {
            address _voter = states.voter;

            if (oldAttached != 0) {
                IVoter(_voter).detachTokenFromGauge(oldAttached, IVotingEscrow(_veRam).ownerOf(oldAttached));
            }
            if (veRamTokenId != 0) {
                IVoter(_voter).attachTokenToGauge(veRamTokenId, IVotingEscrow(_veRam).ownerOf(veRamTokenId));
            }
        }

        // Record new veRamAmount
        if (veRamTokenId != 0) {
            boostedPosition.veRamAmount = int128(IVotingEscrow(_veRam).balanceOfNFT(veRamTokenId)); // can't overflow because bias is lower than locked, which is an int128
        } else {
            boostedPosition.veRamAmount = 0;
        }
    }
}

