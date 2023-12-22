// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./OracleLibrary.sol";
import "./LiquidityAmounts.sol";
import "./ISwapRouter.sol";

import "./TickMath.sol";

import "./ERC20RootVault.sol";
import "./GRamsesStrategy.sol";

contract GRamsesStrategyHelper {
    uint256 public constant Q96 = 2**96;

    function calculateTargetRatioOfToken1(GRamsesStrategy strategy, GRamsesStrategy.State memory state)
        public
        view
        returns (uint256 targetRatioOfToken1X96)
    {
        uint160 aSqrtPriceX96 = TickMath.getSqrtRatioAtTick(state.lowerTick);
        uint160 bSqrtPriceX96 = TickMath.getSqrtRatioAtTick(state.upperTick);
        uint160 cSqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            state.upperTick + strategy.getMutableParams().intervalWidth
        );

        IRamsesV2Pool pool = strategy.getImmutableParams().pool;
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint256[] memory lowerAmountsQ96 = new uint256[](2);
        uint256[] memory upperAmountsQ96 = new uint256[](2);
        (lowerAmountsQ96[0], lowerAmountsQ96[1]) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            aSqrtPriceX96,
            bSqrtPriceX96,
            uint128(state.ratioX96)
        );

        (upperAmountsQ96[0], upperAmountsQ96[1]) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            bSqrtPriceX96,
            cSqrtPriceX96,
            uint128(Q96 - state.ratioX96)
        );

        uint256 amount0 = lowerAmountsQ96[0] + upperAmountsQ96[0];
        uint256 amount1 = lowerAmountsQ96[1] + upperAmountsQ96[1];
        targetRatioOfToken1X96 = FullMath.mulDiv(Q96, amount1, amount0 + amount1);
    }

    function calculateAmountsForSwap(GRamsesStrategy strategy, IERC20RootVault rootVault)
        public
        view
        returns (ISwapRouter.ExactInputSingleParams memory params)
    {
        GRamsesStrategy.Storage memory s = GRamsesStrategy.Storage({
            immutableParams: strategy.getImmutableParams(),
            mutableParams: strategy.getMutableParams()
        });
        uint256 priceX96;
        (uint160 sqrtSpotPriceX96, , , , , , ) = s.immutableParams.pool.slot0();
        priceX96 = FullMath.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, Q96);
        (uint256[] memory currentAmounts, ) = rootVault.tvl();
        (uint256 tokenInIndex, uint256 amountIn) = strategy.calculateAmountsForSwap(
            currentAmounts,
            s.mutableParams.priceImpactD6,
            priceX96,
            calculateTargetRatioOfToken1(strategy, strategy.calculateExpectedState(s))
        );

        params = ISwapRouter.ExactInputSingleParams({
            tokenIn: s.immutableParams.tokens[tokenInIndex],
            tokenOut: s.immutableParams.tokens[tokenInIndex ^ 1],
            fee: s.immutableParams.fee,
            amountIn: amountIn,
            deadline: block.timestamp + 60 * 5,
            recipient: address(s.immutableParams.erc20Vault),
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
    }
}

