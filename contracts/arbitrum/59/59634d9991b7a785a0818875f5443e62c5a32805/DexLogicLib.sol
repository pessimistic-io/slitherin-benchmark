// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {OracleLibrary} from "./OracleLibrary.sol";

import {IV3SwapRouter} from "./IV3SwapRouter.sol";
import {PositionValueMod} from "./PositionValueMod.sol";

import {TransferHelper} from "./TransferHelper.sol";

/// @title DexLogicLib
/// @notice Library for executing trades and managing positions on Uniswap V3.
library DexLogicLib {
    // =========================
    // Constants
    // =========================

    uint256 private constant E18 = 1e18;
    uint256 private constant E6 = 1e6;

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when MEV check detects a deviation of price too high.
    error MEVCheck_DeviationOfPriceTooHigh();

    /// @notice Thrown when zero number of tokens are attempted to be added.
    error DexLogicLib_ZeroNumberOfTokensCannotBeAdded();

    /// @notice Thrown when there are not enough token balances on the vault.LiquidityAmounts
    error DexLogicLib_NotEnoughTokenBalances();

    // =========================
    // Main library logic
    // =========================

    /// @dev Get the current square root price of a Uniswap V3 pool
    /// @param _dexPool Address of the Uniswap V3 pool
    /// @return sqrtPriceX96 Square root price of the pool
    function getCurrentSqrtRatioX96(
        IUniswapV3Pool _dexPool
    ) internal view returns (uint160 sqrtPriceX96) {
        // to call the method slot0 without caring which dex the pool belongs we call without the interface
        (, bytes memory data) = address(_dexPool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (sqrtPriceX96, , , , , , ) = abi.decode(
            data,
            (uint160, int24, uint16, uint16, uint16, uint256, bool)
        );
    }

    /// @dev Retrieve the liquidity of a given NFT position
    /// @param nftId The ID of the NFT position
    /// @param dexNftPositionManager The address of the NonfungiblePositionManager contract
    /// @return Liquidity of the given NFT position
    function getLiquidity(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager
    ) internal view returns (uint128) {
        (, , , , , , , uint128 liquidity, , , , ) = dexNftPositionManager
            .positions(nftId);
        return liquidity;
    }

    /// @notice Calculates the amount of token0 in terms of token1 based on the square root of the price.
    /// @param sqrtPriceX96 The square root of the price, represented as a X96 fixed point number.
    /// @param amount0 The amount of token0.
    /// @return The equivalent amount of token0 in terms of token1.
    function getAmount0InToken1(
        uint160 sqrtPriceX96,
        uint256 amount0
    ) internal pure returns (uint256) {
        uint256 priceX128 = FullMath.mulDiv(
            sqrtPriceX96,
            sqrtPriceX96,
            1 << 64
        );

        return FullMath.mulDiv(priceX128, uint128(amount0), 1 << 128);
    }

    /// @dev Calculates the amount of token1 in terms of token0 based on the square root of the price.
    /// @param sqrtPriceX96 The square root of the price, represented as a X96 fixed point number.
    /// @param amount1 The amount of token1.
    /// @return The equivalent amount of token1 in terms of token0.
    function getAmount1InToken0(
        uint160 sqrtPriceX96,
        uint256 amount1
    ) internal pure returns (uint256) {
        uint256 priceX128 = FullMath.mulDiv(
            sqrtPriceX96,
            sqrtPriceX96,
            1 << 64
        );

        return FullMath.mulDiv(1 << 128, uint128(amount1), priceX128);
    }

    /// @notice Gets the correlation of token0 to token1.
    /// @param amount0 The amount of token0.
    /// @param amount1 The amount of token1.
    /// @param sqrtPriceX96 The square root of the current spot price.
    /// @return res The correlation value between token0 and token1,
    /// represented as an E18 fixed point number.
    ///
    /// @dev res = px / (px + y) * 10^18
    /// where:
    ///  x - amount0
    ///  y - amount1
    ///  p - current spot price
    function getRE18(
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 res) {
        uint256 amount0InToken1 = getAmount0InToken1(sqrtPriceX96, amount0);

        uint256 denominator;
        unchecked {
            denominator = amount0InToken1 + amount1;
        }

        // get the correlation of token0 to token1
        res = FullMath.mulDiv(amount0InToken1, E18, denominator);
    }

    /// @dev Gets the correlation of of token0 to token1 in the current tickRange
    /// by totalPoolLiquidity.
    /// @param minTick The minimum tick of the range.
    /// @param maxTick The maximum tick of the range.
    /// @param totalPoolLiquidity The total liquidity in the pool.
    /// @param sqrtPriceX96 The square root of the current spot price.
    /// @return res The correlation value between token0 and token1 within the specified tick range,
    /// represented as an E18 fixed point number.
    ///
    /// @dev res = px / (px + y) * 10^18
    /// where:
    ///  x - amount0 for total pool liquidity
    ///  y - amount1 for total pool liquidity
    ///  p - current spot price
    function getTargetRE18ForTickRange(
        int24 minTick,
        int24 maxTick,
        uint128 totalPoolLiquidity,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 res) {
        if (totalPoolLiquidity < 1e18) {
            totalPoolLiquidity = 1e18;
        }

        // get the amount of token0 and token1 unified amount of liquidity
        (
            uint256 amount0ForLiquidity,
            uint256 amount1ForLiquidity
        ) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                (TickMath.getSqrtRatioAtTick(minTick)),
                (TickMath.getSqrtRatioAtTick(maxTick)),
                totalPoolLiquidity
            );

        uint256 amount0ForLiquidityInToken1 = getAmount0InToken1(
            sqrtPriceX96,
            amount0ForLiquidity
        );

        uint256 denominator;
        unchecked {
            denominator = amount0ForLiquidityInToken1 + amount1ForLiquidity;
        }

        // get the correlation of token0 to token1
        res = FullMath.mulDiv(amount0ForLiquidityInToken1, E18, denominator);
    }

    /// @dev Fetches position data for a specific NFT ID from the
    /// Uniswap V3 Nonfungible Position Manager.
    /// @param nftId The ID of the NFT.
    /// @param dexNftPositionManager The Nonfungible Position Manager interface.
    /// @return token0 The address of the token0 of the position.
    /// @return token1 The address of the token1 of the position.
    /// @return poolFee The fee tier of the pool in which the position resides.
    /// @return tickLower The lower tick of the position's range.
    /// @return tickUpper The upper tick of the position's range.
    /// @return liquidity The liquidity of the position.
    function getNftData(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager
    )
        internal
        view
        returns (
            address token0,
            address token1,
            uint24 poolFee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        (
            ,
            ,
            token0,
            token1,
            poolFee,
            tickLower,
            tickUpper,
            liquidity,
            ,
            ,
            ,

        ) = dexNftPositionManager.positions(nftId);
    }

    /// @dev Fetches the Uniswap V3 pool for the specified tokens and fee tier.
    /// @param token0 The address of token0.
    /// @param token1 The address of token1.
    /// @param poolFee The fee tier for which to fetch the pool.
    /// @param dexFactory The Uniswap V3 Factory interface.
    /// @return The address of the Uniswap V3 pool for the specified tokens and fee tier.
    function dexPool(
        address token0,
        address token1,
        uint24 poolFee,
        IUniswapV3Factory dexFactory
    ) internal view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(dexFactory.getPool(token0, token1, poolFee));
    }

    /// @dev Checks for potential MEV attacks by comparing the spot price to the oracle price
    /// @param deviationThresholdE18 The maximum allowed deviation between spot and oracle prices
    /// @param _dexPool Address of the Uniswap V3 pool
    /// @param period Period for which the time-weighted average price (TWAP) is calculated
    function MEVCheck(
        uint256 deviationThresholdE18,
        IUniswapV3Pool _dexPool,
        uint32 period
    ) internal view {
        uint160 sqrtPriceX96 = getCurrentSqrtRatioX96(_dexPool);
        uint256 spotPrice = getAmount0InToken1(sqrtPriceX96, E18);

        (int24 timeWeightedAverageTick, ) = OracleLibrary.consult(
            address(_dexPool),
            period
        );

        uint256 oraclePrice = getAmount0InToken1(
            TickMath.getSqrtRatioAtTick(timeWeightedAverageTick),
            E18
        );

        uint256 delta;
        unchecked {
            uint256 proportion = (spotPrice * E18) / oraclePrice;

            delta = proportion > E18 ? proportion - E18 : E18 - proportion;
        }

        if (delta > deviationThresholdE18) {
            revert MEVCheck_DeviationOfPriceTooHigh();
        }
    }

    /// @dev Withdraws a position from the Uniswap V3 Nonfungible Position Manager.
    /// @dev This function decreases the liquidity of a position and collects any fees.
    /// @param nftId The ID of the NFT representing the position to be withdrawn.
    /// @param liquidity The amount of liquidity to be withdrawn.
    /// @param dexNftPositionManager The Nonfungible Position Manager from which the position is withdrawn.
    /// @return amount0 The amount of token0 collected as fees.
    /// @return amount1 The amount of token1 collected as fees.
    function withdrawPositionMEVUnsafe(
        uint256 nftId,
        uint128 liquidity,
        INonfungiblePositionManager dexNftPositionManager
    ) internal returns (uint256, uint256) {
        dexNftPositionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: nftId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // collect all fees
        return collectFees(nftId, dexNftPositionManager);
    }

    /// @dev Collects accumulated fees for a specific position from the Uniswap
    /// V3 Nonfungible Position Manager.
    /// @param nftId The ID of the NFT representing the position for which fees are collected.
    /// @param dexNftPositionManager The Nonfungible Position Manager from which fees are collected.
    /// @return amount0 The amount of token0 collected as fees.
    /// @return amount1 The amount of token1 collected as fees.
    function collectFees(
        uint256 nftId,
        INonfungiblePositionManager dexNftPositionManager
    ) internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = dexNftPositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: nftId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    /// @dev Swaps assets in the Uniswap V3 pool to reach a target correlation between the assets.
    /// @param tickUpper The upper tick of the range in which the liquidity is added.
    /// @param tickLower The lower tick of the range in which the liquidity is added.
    /// @param token0Amount The amount of token0.
    /// @param token1Amount The amount of token1.
    /// @param _dexPool The Uniswap V3 pool used for the swap.
    /// @param token0 The address of token0.
    /// @param token1 The address of token1.
    /// @param poolFee The pool fee rate.
    /// @param dexRouter The Uniswap V3 router to conduct the swap.
    /// @return The amounts of token0 and token1 after the swap.
    function swapToTargetRMEVUnsafe(
        int24 tickUpper,
        int24 tickLower,
        uint256 token0Amount,
        uint256 token1Amount,
        IUniswapV3Pool _dexPool,
        address token0,
        address token1,
        uint24 poolFee,
        IV3SwapRouter dexRouter
    ) internal returns (uint256, uint256) {
        uint160 sqrtPriceX96 = getCurrentSqrtRatioX96(_dexPool);
        uint256 targetRE18 = getTargetRE18ForTickRange(
            tickLower,
            tickUpper,
            _dexPool.liquidity(),
            sqrtPriceX96
        );

        uint256 amount1Target = token1AmountAfterSwapForTargetRE18(
            sqrtPriceX96,
            token0Amount,
            token1Amount,
            targetRE18,
            poolFee
        );

        (token0Amount, token1Amount) = swapAssetsMEVUnsafe(
            token0Amount,
            token1Amount,
            amount1Target,
            targetRE18,
            token0,
            token1,
            poolFee,
            dexRouter
        );

        return (token0Amount, token1Amount);
    }

    /// @dev Calculates the amount of token1 required to achieve a target rate after a swap.
    /// @param sqrtPriceX96 The current square root price of the pool.
    /// @param amount0 The amount of token0.
    /// @param amount1 The amount of token1.
    /// @param targetRE18 The target rate.
    /// @param poolFeeE6 The pool fee rate.
    /// @return The target amount of token1.
    ///
    /// @dev y1 = (R1 - Rtg) / (R1 - Rtg * poolFee / feeMax) * (y0 +  p * x0 * (F1 - poolFee) / feeMax)
    /// where:
    ///  y1 - target amount token1
    ///  R1 - 1e14
    ///  Rtg - target rate (from getTargetRE18ForTickRange)
    ///  feeMax - 1e6
    ///  y0 - initial amount token1
    ///  x0 - initial amount token0
    ///  p - current pool price
    ///
    /// source: https://www.desmos.com/calculator/c3a9zuij81
    function token1AmountAfterSwapForTargetRE18(
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        uint256 targetRE18,
        uint24 poolFeeE6
    ) internal pure returns (uint256) {
        uint256 px0 = getAmount0InToken1(sqrtPriceX96, amount0);

        uint256 oneMinusRtgE18 = E18 - targetRE18;
        uint256 oneMinusRtgFee = E18 - (targetRE18 * poolFeeE6) / E6;

        uint256 firstMultiplier = (oneMinusRtgE18 * E18) / oneMinusRtgFee;
        uint256 secondMultiplier = ((E6 - poolFeeE6) * px0) / E6 + amount1;

        return (firstMultiplier * secondMultiplier) / E18;
    }

    /// @dev Calculates the amount of token0 required to achieve a target rate after a swap.
    /// @param sqrtPriceX96 The current square root price of the pool.
    /// @param amount1 The amount of token1.
    /// @param targetRE18 The target rate.
    /// @return The target amount of token0.
    ///
    /// @dev x1 = Rtg / (R1 - Rtg) * (y1 / p)
    /// where:
    ///  y1 - target amount token1
    ///  R1 - 1e14
    ///  Rtg - target rate (from getTargetRE18ForTickRange)
    ///  p - current pool price
    ///
    /// source: https://www.desmos.com/calculator/c3a9zuij81
    function token0AmountAfterSwapForTargetRE18(
        uint160 sqrtPriceX96,
        uint256 amount1,
        uint256 targetRE18
    ) internal pure returns (uint256) {
        uint256 py1 = getAmount1InToken0(sqrtPriceX96, amount1);

        uint256 oneMinusRtgE18 = E18 - targetRE18;

        uint256 multiplier = FullMath.mulDiv(targetRE18, E18, oneMinusRtgE18);

        return (multiplier * py1) / E18;
    }

    /// @dev Swap tokens in a given direction, ensuring the resulting balance matches the target.
    /// @dev This function might revert if the swap cannot be executed.
    /// @param amount0 Amount of token0.
    /// @param amount1 Amount of token1.
    /// @param amount1Target The target amount for token1.
    /// @param targetR The target correlation.
    /// @param token0 Address of token0.
    /// @param token1 Address of token1.
    /// @param poolFee The pool's fee rate.
    /// @param dexRouter The router to facilitate the swap.
    /// @return The new balances of token0 and token1.
    function swapAssetsMEVUnsafe(
        uint256 amount0,
        uint256 amount1,
        uint256 amount1Target,
        uint256 targetR,
        address token0,
        address token1,
        uint24 poolFee,
        IV3SwapRouter dexRouter
    ) internal returns (uint256, uint256) {
        // swap tokens
        if (amount1 > amount1Target) {
            uint256 amountForSwap;
            unchecked {
                amountForSwap = amount1 - amount1Target;
            }

            uint256 amountOut = swapExactInputMEVUnsafe(
                token1,
                token0,
                poolFee,
                amountForSwap,
                dexRouter
            );
            unchecked {
                // update balances
                return (amount0 + amountOut, amount1Target);
            }
        } else if (amount1Target > amount1) {
            if (targetR == 0) {
                // if token0 is not needed at all
                uint256 amountOut = swapExactInputMEVUnsafe(
                    token0,
                    token1,
                    poolFee,
                    amount0,
                    dexRouter
                );
                unchecked {
                    // update balances
                    return (0, amount1 + amountOut);
                }
            } else {
                uint256 amountForSwap;
                unchecked {
                    amountForSwap = amount1Target - amount1;
                }

                // Since we don't know the exact number of tokens to be given in the SwapExactOutput method,
                // we do approve for the entire transferred balance of token0
                TransferHelper.safeApprove(token0, address(dexRouter), amount0);

                uint256 amountIn = swapExactOutputMEVUnsafe(
                    token0,
                    token1,
                    poolFee,
                    amountForSwap,
                    dexRouter
                );

                unchecked {
                    // update balances
                    // underflow is impossible, the check was during the swap
                    return (amount0 - amountIn, amount1Target);
                }
            }
        } else {
            return (amount0, amount1);
        }
    }

    /// @dev Swap an exact input amount for as much output as possible.
    /// @dev This function might revert if the swap cannot be executed.
    /// @param tokenIn The token to be provided.
    /// @param tokenOut The token to be received.
    /// @param poolFee The pool's fee rate.
    /// @param amountForSwap Amount of `tokenIn` to be swapped.
    /// @param dexRouter The router to facilitate the swap.
    /// @return The amount of `tokenOut` received.
    function swapExactInputMEVUnsafe(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountForSwap,
        IV3SwapRouter dexRouter
    ) internal returns (uint256) {
        TransferHelper.safeApprove(tokenIn, address(dexRouter), amountForSwap);

        return
            dexRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: poolFee,
                    recipient: address(this),
                    amountIn: amountForSwap,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    /// @dev Swap as input as needed to receive the exact output amount.
    /// @dev This function might revert if the swap cannot be executed.
    /// @param tokenIn The token to be provided.
    /// @param tokenOut The token to be received.
    /// @param poolFee The pool's fee rate.
    /// @param amountForSwap Amount of `tokenOut` to be received.
    /// @param dexRouter The router to facilitate the swap.
    /// @return The amount of `tokenIn` spent.
    function swapExactOutputMEVUnsafe(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountForSwap,
        IV3SwapRouter dexRouter
    ) internal returns (uint256) {
        return
            dexRouter.exactOutputSingle(
                IV3SwapRouter.ExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: poolFee,
                    recipient: address(this),
                    amountOut: amountForSwap,
                    amountInMaximum: type(uint256).max,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    /// @dev Mints a new NFT.
    /// @dev This function might revert if the minting cannot be executed.
    /// @param token0Amount Amount of token0.
    /// @param token1Amount Amount of token1.
    /// @param tickLower The lower end of the tick range.
    /// @param tickUpper The upper end of the tick range.
    /// @param token0 Address of token0.
    /// @param token1 Address of token1.
    /// @param poolFee The pool's fee rate.
    /// @param dexNftPositionManager The position manager to facilitate minting.
    /// @return The ID of the minted NFT.
    function mintNftMEVUnsafe(
        uint256 token0Amount,
        uint256 token1Amount,
        int24 tickLower,
        int24 tickUpper,
        address token0,
        address token1,
        uint24 poolFee,
        INonfungiblePositionManager dexNftPositionManager
    ) internal returns (uint256) {
        // if nothing is added to the new token, then revert,
        // since the nft will not be created anyway
        if (token0Amount == 0 && token1Amount == 0) {
            revert DexLogicLib_ZeroNumberOfTokensCannotBeAdded();
        }

        if (token0 > token1) {
            (token0, token1) = ((token1, token0));
            (token0Amount, token1Amount) = ((token1Amount, token0Amount));
        }

        TransferHelper.safeApprove(
            token0,
            address(dexNftPositionManager),
            token0Amount
        );
        TransferHelper.safeApprove(
            token1,
            address(dexNftPositionManager),
            token1Amount
        );

        INonfungiblePositionManager.MintParams memory mintParams;
        mintParams.token0 = token0;
        mintParams.token1 = token1;
        mintParams.fee = poolFee;
        mintParams.tickLower = tickLower;
        mintParams.tickUpper = tickUpper;
        mintParams.amount0Desired = token0Amount;
        mintParams.amount1Desired = token1Amount;
        mintParams.recipient = address(this);
        mintParams.deadline = block.timestamp;

        (uint256 nftId, , , ) = dexNftPositionManager.mint(mintParams);
        return (nftId);
    }

    /// @dev Increases the liquidity of a specific NFT position.
    /// @dev This function might revert if the operation cannot be executed.
    /// @param nftId The ID of the NFT position.
    /// @param token0Amount Amount of token0.
    /// @param token1Amount Amount of token1.
    /// @param dexNftPositionManager The position manager to facilitate liquidity increase.
    function increaseLiquidityMEVUnsafe(
        uint256 nftId,
        uint256 token0Amount,
        uint256 token1Amount,
        INonfungiblePositionManager dexNftPositionManager
    ) internal {
        if (token0Amount == 0 && token1Amount == 0) {
            return;
        }

        dexNftPositionManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: nftId,
                amount0Desired: token0Amount,
                amount1Desired: token1Amount,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
    }

    /// @dev Validates that the vault has enough balance of a token.
    /// @dev This function might revert if the balance is insufficient.
    /// @param token The token's address.
    /// @param tokenAmount The required amount.
    function validateTokenBalance(
        address token,
        uint256 tokenAmount
    ) internal view {
        uint256 tokenBalance = TransferHelper.safeGetBalance(
            token,
            address(this)
        );

        if (tokenAmount > tokenBalance) {
            revert DexLogicLib_NotEnoughTokenBalances();
        }
    }

    /// @dev Retrieves the fees accrued to a specific NFT position.
    /// @dev This function uses PositionValueMod.fees internally.
    /// @param nftId The ID of the NFT position.
    /// @param _dexPool The relevant Uniswap V3 pool.
    /// @param dexNftPositionManager The position manager to query fees.
    /// @return The fees of token0 and token1.
    function fees(
        uint256 nftId,
        IUniswapV3Pool _dexPool,
        INonfungiblePositionManager dexNftPositionManager
    ) internal view returns (uint256, uint256) {
        (uint256 amount0, uint256 amount1) = PositionValueMod.fees(
            dexNftPositionManager,
            nftId,
            _dexPool
        );
        return (amount0, amount1);
    }

    /// @dev Calculates the total value locked in a specific NFT position.
    /// @dev This function uses PositionValueMod.total internally.
    /// @param nftId The ID of the NFT position.
    /// @param _dexPool The relevant Uniswap V3 pool.
    /// @param dexNftPositionManager The position manager to calculate TVL.
    /// @return The amounts of token0 and token1.
    function tvl(
        uint256 nftId,
        IUniswapV3Pool _dexPool,
        INonfungiblePositionManager dexNftPositionManager
    ) internal view returns (uint256, uint256) {
        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(_dexPool);

        (uint256 amount0, uint256 amount1) = PositionValueMod.total(
            dexNftPositionManager,
            nftId,
            sqrtPriceX96,
            _dexPool
        );
        return (amount0, amount1);
    }

    /// @notice Retrieves the principal amounts for a specific NFT position.
    /// @dev This function uses PositionValueMod.principal internally.
    /// @param nftId The ID of the NFT position.
    /// @param _dexPool The relevant Uniswap V3 pool.
    /// @param dexNftPositionManager The position manager to retrieve principal amounts.
    /// @return The principal amounts of token0 and token1.
    function principal(
        uint256 nftId,
        IUniswapV3Pool _dexPool,
        INonfungiblePositionManager dexNftPositionManager
    ) internal view returns (uint256, uint256) {
        uint160 sqrtPriceX96 = DexLogicLib.getCurrentSqrtRatioX96(_dexPool);

        (uint256 amount0, uint256 amount1) = PositionValueMod.principal(
            dexNftPositionManager,
            nftId,
            sqrtPriceX96
        );
        return (amount0, amount1);
    }
}

