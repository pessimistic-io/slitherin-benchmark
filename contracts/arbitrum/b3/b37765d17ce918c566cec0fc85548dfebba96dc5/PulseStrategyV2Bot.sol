// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./PulseStrategyV2.sol";
import "./ISwapRouter.sol";

contract PulseStrategyV2Bot {
    using SafeERC20 for IERC20;

    PulseStrategyV2 public immutable strategy;
    ISwapRouter public immutable swapRouter;

    constructor(PulseStrategyV2 strategy_, ISwapRouter swapRouter_) {
        strategy = strategy_;
        swapRouter = swapRouter_;
    }

    function rebalance() external returns (address[] memory newTokens) {
        (
            PulseStrategyV2.ImmutableParams memory immutableParams,
            ,
            PulseStrategyV2.VolatileParams memory volatileParams
        ) = strategy.parameters();

        address token = volatileParams.token;
        address vault = immutableParams.vault;
        IUniswapV3Pool pool = immutableParams.pool;

        address token0 = pool.token0();
        address token1 = pool.token1();
        UniV3Token newToken;
        uint160 sqrtPriceX96;

        {
            IERC20(token).safeTransferFrom(vault, address(this), IERC20(token).balanceOf(vault));
            UniV3Token(token).compound();
            UniV3Token(token).burn(UniV3Token(token).convertSupplyToLiquidity(IERC20(token).balanceOf(address(this))));

            int24 spotTick;
            (sqrtPriceX96, spotTick, , , , , ) = pool.slot0();
            spotTick -= spotTick % pool.tickSpacing();

            {
                (int24 lowerTick, int24 upperTick) = strategy.calculateNewPosition(
                    UniV3Token(token).tickLower(),
                    UniV3Token(token).tickUpper(),
                    spotTick,
                    volatileParams.forceRebalanceFlag
                );
                (, newToken) = UniV3Token(token).registry().createToken(
                    abi.encode(token0, token1, pool.fee(), lowerTick, upperTick, "MLT", "MLT")
                );
            }
        }

        uint256 amount0 = IERC20(token0).balanceOf(address(this));
        uint256 amount1 = IERC20(token1).balanceOf(address(this));
        require(amount0 + amount1 > 0);
        uint256 tokenInIndex;
        uint256 amountIn;
        {
            uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2 ** 96);
            (tokenInIndex, amountIn) = newToken.calculateAmountsForSwap(
                [amount0, amount1],
                priceX96,
                newToken.calculateTargetRatioOfToken1(sqrtPriceX96, priceX96)
            );
        }

        address[2] memory tokens = [token0, token1];
        IERC20(tokens[tokenInIndex]).safeApprove(address(swapRouter), amountIn);
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokens[tokenInIndex],
                tokenOut: tokens[tokenInIndex ^ 1],
                fee: pool.fee(),
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        amount0 = IERC20(token0).balanceOf(address(this));
        amount1 = IERC20(token1).balanceOf(address(this));
        IERC20(token0).safeApprove(address(newToken), amount0);
        IERC20(token1).safeApprove(address(newToken), amount1);

        newToken.mint(amount0, amount1, 0);
        newTokens = new address[](1);
        newTokens[0] = address(newToken);

        newToken.transfer(vault, newToken.balanceOf(address(this)));
    }
}

