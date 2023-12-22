// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma abicoder v2;

import "./SushiBaseLiquidityManager.sol";

contract SushiSinglePositionLiquidityManager is SushiBaseLiquidityManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Storage

    /// @dev The vault's position's data.
    ///      This represents the active position of the vault inside uniswap.
    ///      lowerTick is the lower bound of the position at that index.
    ///      upperTick is the upper bound of the position at that index.
    int24 public lowerTick;
    int24 public upperTick;

    // External Functions

    /// @dev Internal function to pull funds from pool
    ///      Update position if necessary, then deposit funds into pool.
    ///      Reverts if the vault does not own any liquidity or tokens.
    ///      tick requirements:
    ///        lowerTick must be lower than upperTick
    ///        lowerTick must be greater than or equal to the tick min (-887272)
    ///        upperTick must be less than or equal to the tick max (887272)
    ///        lowerTick and upperTick must be divisible by the pool tickSpacing--
    ///      A 0.05% fee pool has tick spacing of 10, 0.3% has tick spacing 60.
    ///      And 1% has tick spacing 200.
    /// @param totalWeight The share of liquidity we want deposited, multiplied by 10,000.
    ///           A value of 10,000 means we want to deposit all tokens into uniswap.
    ///           A value of 0 means we just want all the liquidity out.
    ///           Note that values above 10,000 are not explicitly prohibited
    ///           but will generally cause the tend to fail and revert.
    /// @param newLowerTick The lower tick of the new position to be created
    /// @param newUpperTick The upper tick of the new position to be created.
    ///           Note that if both are set to the same value,
    ///           the vault's position will not be updated.
    ///           Gas will be cheapest if both are set to zero in this case.
    /// @param swapAmount The amount to be swapped from one token to another this tend.
    ///           zeroForOne if positive, oneForZero if negative.
    /// @param sqrtPriceLimitX96 The slippage limit of the swap.
    ///           Protections elsewhere prevent extreme slippage if the keeper calling
    ///           this function is malicious, but this is the first line of defense
    ///           against MEV attacks.
    function tend(
        uint256 totalWeight,
        int24 newLowerTick,
        int24 newUpperTick,
        int248 swapAmount,
        uint160 sqrtPriceLimitX96
    ) external onlyRole(MANAGER_ROLE) whenNotPaused {
        // Get current pool state
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        // currentTick must be close enough to TWAP tick to avoid MEV exploit
        // This is essentially a way to prevent a flashloan attack
        // even if sqrtPriceLimit is set incorrectly.
        _checkVolatility(currentTick);

        // Withdraw liquidity from Uniswap pool by passing in 1 and 1
        // (indicating we're withdrawing 100% of liquidity)
        _burnAndCollect(1, 1);

        // Update positions if desired.
        // If both are set to zero (or just the same amount) then we won't update the positions,
        // instead leaving them as they were.
        if (newLowerTick != newUpperTick) {
            lowerTick = newLowerTick;
            upperTick = newUpperTick;
        }

        // Perform a swap if desired.
        if (swapAmount > 0) {
            bool zeroForOne = swapAmount > 0;
            pool.swap(
                address(this),
                zeroForOne,
                zeroForOne ? int256(swapAmount) : -int256(swapAmount),
                sqrtPriceLimitX96,
                ""
            );

            // Update sqrtPriceX96; it will have moved due to the swap
            (sqrtPriceX96, , , , , , ) = pool.slot0();
        }

        uint256 balance0 = _getBalance0();
        uint256 balance1 = _getBalance1();

        emit Snapshot(sqrtPriceX96, balance0, balance1, totalSupply());

        // Create new positions in Uniswap
        if (totalWeight > 0) {
            _setBins(
                sqrtPriceX96,
                // balance0 adjusted by totalWeight
                FullMath.mulDiv(balance0, totalWeight, 1e4),
                // balance1 adjusted by totalWeight
                FullMath.mulDiv(balance1, totalWeight, 1e4),
                swapAmount
            );
        }
    }

    // Public Functions

    /// @dev Burns vault position, updating fees owed to that position.
    ///      Call this before calling getTotalAmounts if total amounts must include fees.
    ///      There's a function in the periphery to do so through a static call.
    function poke() public override {
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;
        (uint128 positionLiquidity, , , , ) = _position(
            _lowerTick,
            _upperTick
        );

        // Update fees owed.
        if (positionLiquidity > 0) {
            pool.burn(_lowerTick, _upperTick, 0);
        }
    }

    /// @dev Calculates the vault's total holdings of token0 and token1
    ///      in other words, how much of each token the vault would hold if it withdrew
    ///      all its liquidity from Uniswap.
    ///      This function DOES NOT include fees earned since the last burn.
    ///      To include fees, first poke() and then call getTotalAmounts.
    ///      There's a function inside the periphery to do so.
    function getTotalAmounts()
        public
        view
        override
        returns (uint256 total0, uint256 total1)
    {
        // Start with tokens currently held inside the vault
        total0 = _getBalance0();
        total1 = _getBalance1();

        // These include fees to steer and strategist,
        // which we remove before adding them to total0 and total1.
        // uint256 totalT0Fees;
        // uint256 totalT1Fees;

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        // Get calculated amounts of tokens contained within position
        (
            uint256 amt0,
            uint256 amt1,
            uint256 fees0,
            uint256 fees1
        ) = _getPositionAmounts(sqrtPriceX96, lowerTick, upperTick);

        // Increase balances
        total0 = total0.add(amt0);
        total1 = total1.add(amt1);

        // Subtract protocol fees from position fee earned,
        // then add the (now LP-owned) remaining tokens to total balances
        total0 = total0.add(
            FullMath.mulDiv(fees0, ONE_MINUS_FEE, FEE_DIVISOR)
        );
        total1 = total1.add(
            FullMath.mulDiv(fees1, ONE_MINUS_FEE, FEE_DIVISOR)
        );
    }

    // Internal Functions

    /// @dev Given desired positions, desired relative weights, and a current token amount,
    ///      This function deposits as much liquidity as possible into each position
    ///      while respecting relative weights.
    /// @param sqrtPriceX96 The current sqrtPriceX96 of the pool
    /// @param t0ToDeposit The vault's current balance of token0 ready to be deposited
    ///                 (excluding steer and strategist fees)
    /// @param t1ToDeposit The vault's current balance of token1 ready to be deposited
    ///                 (excluding steer and strategist fees)
    /// @param swapAmount The amount to be swapped from one token to another this tend.
    ///                   zeroForOne if positive, oneForZero if negative.
    ///                   Here it is mainly used to determine which direction the swap was,
    ///                   so that we can check whether the swap was too large.
    function _setBins(
        uint160 sqrtPriceX96,
        uint256 t0ToDeposit,
        uint256 t1ToDeposit,
        int256 swapAmount
    ) internal {
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(_lowerTick),
            TickMath.getSqrtRatioAtTick(_upperTick),
            t0ToDeposit,
            t1ToDeposit
        );

        // Create the position inside the pool.
        if (liquidity > 0) {
            pool.mint(address(this), _lowerTick, _upperTick, liquidity, "");
        }

        // Check post-mint balances.
        // We need to check that less than 5% of the TO token (i.e. the token we swapped into) remains post-mint.
        // Having the right liquidity ratio is extremely valuable,
        // but the main thing we're protecting against here is dynamic data that swaps more than it should.

        // As an example, assume a malicious keeper has flashloaned the uniswap V3 pool
        // into a very bad exchange rate before handling the swap.
        // If exchange rate is extremely high token1PerToken0, exploiter will want to swap
        // from token1 to token0 (going the other way just helps the liquidity manager)
        // But the positions will be entirely in token1.
        // The check below ensures that no more than 5% of the total contract token0 remains undeposited,
        // a reliable indicator that the correct amount of token1 was swapped.

        // This combined with the TWAP check makes flashloan exploits extremely difficult for a single keeper.

        // If swapAmount > 0, that means zeroForOne. Otherwise, oneForZero.
        // No overflow checks here because some kind of overflow exploit is
        // both implausible and would just cause a revert.
        if (swapAmount > 0) {
            // Require that at least 95% of t1 has been deposited
            // (ensuring that swap amount wasn't too great)
            require(_getBalance1() < (t1ToDeposit * 5) / 100, "swap");
        } else if (swapAmount < 0) {
            // Require that at least 95% of t0 has been deposited
            // (ensuring that swap amount wasn't too great)
            require(_getBalance0() < (t0ToDeposit * 5) / 100, "swap");
        }
    }

    /// @dev Withdraws liquidity from position, allocating fees correctly in the process.
    /// @param shares LP shares being withdrawn
    /// @param totalShares Total # of LP tokens in the vault
    /// @param t0 token0 earned from burned liquidity + fees.
    ///           Only includes burned + fees corresponding to LP shares being withdrawn (100% if tend)
    /// @param t1 token1 earned from burned liquidity + fees
    function _burnAndCollect(
        uint256 shares,
        uint256 totalShares
    ) internal override returns (uint256 t0, uint256 t1) {
        // Cache lowerTick and upperTick to minimize SLOADs
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;

        // Burn() and then withdraw correct amount of liquidity.

        // Get position liquidity. If we don't want all of it,
        // here is where we specify how much we want (liquidity * fraction of pool which is being withdrawn)
        (uint128 totalPositionLiquidity, , , , ) = _position(
            _lowerTick,
            _upperTick
        );

        uint128 liquidityToBurn = uint128(
            FullMath.mulDiv(totalPositionLiquidity, shares, totalShares)
        );

        // amountsOwed are always pulled with liquidity in this contract,
        // so if position liquidity is 0, no need to withdraw anything.
        if (liquidityToBurn == 0) {
            return (0, 0);
        }

        // If there is liquidity to withdraw, proceed to withdraw it and also collect fees.

        // Amount burned in each position.
        // Corresponds to amount of liquidity withdrawn (i.e. doesn't include fees).
        (t0, t1) = pool.burn(_lowerTick, _upperTick, liquidityToBurn);

        // Collect all owed tokens including earned fees
        (uint256 collect0, uint256 collect1) = pool.collect(
            address(this),
            _lowerTick,
            _upperTick,
            type(uint128).max,
            type(uint128).max
        );

        // Fees earned by liquidity inside uniswap = collected - burned.
        // First we allocate some to steer and some to strategist.
        // The remainder is the fees earned by LPs.
        // So after that we add remainder * shares / totalShares,
        // and that gives us t0 and t1 allocated to whatever's being withdrawn.

        // Since burned will never be greater than collected,
        // no need to check for underflow here.
        uint256 fees0 = collect0 - t0;
        uint256 fees1 = collect1 - t1;

        // Emit fee info
        emit FeesEarned(fees0, fees1);

        // Update accrued protocol fees
        if (fees0 > 0) {
            uint256 totalCut0 = FullMath.mulDiv(fees0, TOTAL_FEE, FEE_DIVISOR);

            // Subtract fees going to strategist/steer from fees going to vault
            fees0 -= totalCut0;

            // Allocate fee amounts to strategist/steer correctly
            uint256 feesToSteer0 = FullMath.mulDiv(
                totalCut0,
                STEER_FRACTION_OF_FEE,
                FEE_DIVISOR
            );

            // Increase fees
            accruedSteerFees0 = accruedSteerFees0.add(feesToSteer0);
            // Add fees to strategist
            // Since steer fees = (totalCut * steerFraction) / 1e4,
            // and steerFraction cannot be greater than 1e4,
            // no need to check for underflow here.
            accruedStrategistFees0 = accruedStrategistFees0.add(
                totalCut0 - feesToSteer0
            );
        }

        if (fees1 > 0) {
            uint256 totalCut1 = FullMath.mulDiv(fees1, TOTAL_FEE, FEE_DIVISOR);

            fees1 -= totalCut1;

            uint256 feesToSteer1 = FullMath.mulDiv(
                totalCut1,
                STEER_FRACTION_OF_FEE,
                FEE_DIVISOR
            );

            accruedSteerFees1 = accruedSteerFees1.add(feesToSteer1);
            accruedStrategistFees1 = accruedStrategistFees1.add(
                totalCut1 - feesToSteer1
            );
        }

        // Add fees earned by burned position to burned amount
        t0 = t0.add(FullMath.mulDiv(fees0, shares, totalShares));
        t1 = t1.add(FullMath.mulDiv(fees1, shares, totalShares));
    }
}

