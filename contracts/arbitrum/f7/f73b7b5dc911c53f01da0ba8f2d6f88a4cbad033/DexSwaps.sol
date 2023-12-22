// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;
import "./TickMath.sol";
import "./FullMath.sol";
// import "../interfaces/IUniswapV3Pool.sol";
// import "../interfaces/IUniswapV2Router02.sol";
// import "../interfaces/IUniswapV2Router01.sol";
import "./console.sol";
// import "../interfaces/IFactoryCurve.sol";
import "./IPoolCurve.sol";
// import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
// import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
// import "../interfaces/IRouterSOLIDLY.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./IPoolUniV2.sol";
import "./IPoolUniV3.sol";
import "./IPoolKyberswap.sol";
import "./IPoolKyberswapV2.sol";
import "./IPoolVelodrome.sol";
import "./IPoolCamelot.sol";

import "./IPoolAddressesProvider.sol";
import "./SafeMath.sol";
import "./IPoolDODO.sol";
import "./IAsset.sol";
import "./IBalancerVault.sol";
// import "../interfaces/IFactoryCurve.sol";
import "./IPoolSaddle.sol";
import "./IPoolMetavault.sol";
import "./IPoolGmx.sol";

contract DexSwaps {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct SwapInfo {
        address pool;
        address tokenIn;
        address tokenOut;
        uint8 poolType;
        bytes32 poolId;
    }

    struct Balance {
        string symbol;
        address token;
        uint8 decimals;
        uint256 balance;
        uint256 balanceUSD;
    }
    uint256 constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function SwapUniswapV2(SwapInfo memory info, uint256 amountIn) internal {
        // // console.log("*********** SwapUniswapV2 ***********");
        // tokensBalance(info.tokenIn, info.tokenOut);

        uint112 _reserve0;
        uint112 _reserve1;
        uint256 reserveIn;
        uint256 reserveOut;

        // approve the tokenIn on the pool
        approveToken(info.tokenIn, info.pool);

        // transfer: This function allows an address to send tokens to another address.
        IERC20(info.tokenIn).transfer(address(info.pool), amountIn);

        // Use IPoolUniV2 to get token 0 and 1
        address token0 = IPoolUniV2(info.pool).token0();
        address token1 = IPoolUniV2(info.pool).token1();

        //get the reserves from the pool
        (_reserve0, _reserve1, ) = IPoolUniV2(info.pool).getReserves();
        reserveIn = info.tokenIn == token0 ? _reserve0 : _reserve1;
        reserveOut = info.tokenIn == token1 ? _reserve0 : _reserve1;

        //make operatios to take amountOut
        uint256 amountOut;
        // uint256 amountIn = amountIn;
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;

        // validate if the amountOut is for token0 or token1
        uint256 amount0Out = info.tokenIn == token0 ? 0 : amountOut;
        uint256 amount1Out = info.tokenIn == token1 ? 0 : amountOut;

        //make the swap
        IPoolUniV2(info.pool).swap(amount0Out, amount1Out, address(this), "");
        // ///tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapUniswapV3(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("*********** SwapUniswapV3 ***********");
        bool zeroForOne;
        // ///tokensBalance(info.tokenIn, info.tokenOut);
        address token0 = IPoolUniV3(info.pool).token0();
        (uint160 sqrtPriceLimitX96, , , , , , ) = IPoolUniV3(info.pool).slot0();

        if (token0 == info.tokenIn) {
            zeroForOne = true;
            sqrtPriceLimitX96 = (sqrtPriceLimitX96 * 900) / 1000;
        } else {
            zeroForOne = false;
            sqrtPriceLimitX96 = (sqrtPriceLimitX96 * 1100) / 1000;
        }

        bytes memory data = abi.encode(info.pool, info.tokenIn, zeroForOne);

        IPoolUniV3(info.pool).swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            sqrtPriceLimitX96,
            data
        );

        // ///tokensBalance(info.tokenIn, info.tokenOut);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        (address pool, address tokenIn, bool zeroForOne) = abi.decode(
            data,
            (address, address, bool)
        );
        // console.log("uniswapV3SwapCallback");

        // console.logInt(amount0Delta);
        // console.logInt(amount1Delta);

        if (zeroForOne) {
            IERC20(tokenIn).transfer(address(pool), uint256(amount0Delta));
        } else {
            IERC20(tokenIn).transfer(address(pool), uint256(amount1Delta));
        }
        // console.log("*********** uniswapV3SwapCallback  transfer ***********");
    }

    function SwapMetavault(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n*********** SwapMetavault ***********");
        //tokensBalance(info.tokenIn, info.tokenOut);

        IERC20(info.tokenIn).transfer(info.pool, amountIn);
        IPoolMetavault(info.pool).swap(
            info.tokenIn,
            info.tokenOut,
            address(this)
        );
        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapGmx(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n*********** SwapGmx ***********");
        //tokensBalance(info.tokenIn, info.tokenOut);

        IERC20(info.tokenIn).transfer(info.pool, amountIn);
        IPoolGmx(info.pool).swap(info.tokenIn, info.tokenOut, address(this));
        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapCamelot(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n*********** SwapGmx ***********");
        //tokensBalance(info.tokenIn, info.tokenOut);

        //appruve
        // approveToken(info.tokenIn, info.pool);
        IERC20(info.tokenIn).transfer(info.pool, amountIn);

        address token0 = IPoolUniV2(info.pool).token0();
        // address token1 = IPoolUniV2(info.pool).token1();

        uint256 amount = IPoolCamelot(info.pool).getAmountOut(
            amountIn,
            info.tokenIn
        );
        console.log("amount", amount);

        uint256 amount0Out;
        uint256 amount1Out;

        if (info.tokenOut == token0) {
            amount0Out = amount;
        } else {
            amount1Out = amount;
        }

        IPoolCamelot(info.pool).swap(amount0Out, amount1Out, address(this), "");
        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapDodo(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n***********DexSwaps SwapDodo ***********");

        // tokensBalance(info.tokenIn, info.tokenOut);

        IERC20(info.tokenIn).transfer(info.pool, amountIn);
        // console.log("info.pool", info.pool);
        if (IPoolDODO(info.pool)._BASE_TOKEN_() == info.tokenIn) {
            // console.log("sellBase");
            IPoolDODO(info.pool).sellBase(address(this)); //WMATIC
        } else if (IPoolDODO(info.pool)._QUOTE_TOKEN_() == info.tokenIn) {
            // console.log("_QUOTE_TOKEN_");

            IPoolDODO(info.pool).sellQuote(address(this)); //USDC`
        }

        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapDodoClassic(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n***********DexSwaps SwapDodo ***********");
        // tokensBalance(info.tokenIn, info.tokenOut);

        approveToken(info.tokenIn, info.pool);
        uint256 amountOut;

        // console.log("\ninfo.pool", info.pool);
        if (IPoolDODO(info.pool)._BASE_TOKEN_() == info.tokenIn) {
            amountOut = IPoolDODO(info.pool).queryBuyBaseToken(amountIn);

            // console.log("\nsellBaseToken amountOut", amountOut);

            IPoolDODO(info.pool).sellBaseToken(amountOut, amountOut, "");
        } else if (IPoolDODO(info.pool)._QUOTE_TOKEN_() == info.tokenIn) {
            amountOut = IPoolDODO(info.pool).querySellBaseToken(amountIn);

            // console.log("\nbuyBaseToken amountOut", amountOut);

            IPoolDODO(info.pool).buyBaseToken(amountOut, amountOut, "");
        }

        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapKyberswapV1(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n***********DexSwaps SwapKyberswapV1 ***********");
        // tokensBalance(info.tokenIn, info.tokenOut);

        IERC20(info.tokenIn).transfer(address(info.pool), amountIn);
        (
            ,
            ,
            uint256 vReserveIn,
            uint256 vReserveOut,
            uint256 feeInPrecision
        ) = IPoolKyberswap(info.pool).getTradeInfo();
        uint256 PRECISION = 1e18;

        uint256 amountInWithFee = amountIn
            .mul(PRECISION.sub(feeInPrecision))
            .div(PRECISION);

        uint256 amount0Out;
        uint256 amount1Out;
        uint256 denominator;
        if (IPoolKyberswap(info.pool).token0() == info.tokenIn) {
            denominator = vReserveIn.add(amountInWithFee);
            amount1Out = amountInWithFee.mul(vReserveOut).div(denominator);
        } else {
            denominator = vReserveOut.add(amountInWithFee);
            amount0Out = amountInWithFee.mul(vReserveIn).div(denominator);
        }

        IPoolKyberswap(info.pool).swap(
            amount0Out,
            amount1Out,
            address(this),
            ""
        );

        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapKyberswapV2(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n***********DexSwaps SwapKiberswapV2 ***********");
        // tokensBalance(info.tokenIn, info.tokenOut);

        IPoolKyberswapV2 pool = IPoolKyberswapV2(info.pool);

        (uint160 sqrtPriceLimitX96, , , ) = pool.getPoolState();
        bool zeroForOne;

        if (pool.token0() == info.tokenIn) {
            zeroForOne = true;
            sqrtPriceLimitX96 = (sqrtPriceLimitX96 * 900) / 1000;
        } else {
            zeroForOne = false;

            sqrtPriceLimitX96 = (sqrtPriceLimitX96 * 1100) / 1000;
        }
        pool.swap(
            address(this),
            int256(amountIn),
            zeroForOne,
            sqrtPriceLimitX96,
            ""
        );
        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    // function SwapVelodrome(SwapInfo memory info, uint256 amountIn) internal {
    //     // console.log("\n***********DexSwaps SwapVelodrome ***********");
    //     // tokensBalance(info.tokenIn, info.tokenOut);

    //     IERC20(info.tokenIn).transfer(info.pool, amountIn);

    //     IPoolVelodrome pool = IPoolVelodrome(info.pool);

    //     uint256 amountOut = pool.getAmountOut(amountIn, info.tokenIn);

    //     uint256 amount0Out = info.tokenIn == pool.token0() ? 0 : amountOut;
    //     uint256 amount1Out = info.tokenIn != pool.token0() ? 0 : amountOut;

    //     pool.swap(amount0Out, amount1Out, address(this), "");
    //     // tokensBalance(info.tokenIn, info.tokenOut);
    // }

    function SwapSaddle(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n*********** SwapSaddle ***********");
        // tokensBalance(info.tokenIn, info.tokenOut);

        uint8 i = IPoolSaddle(info.pool).getTokenIndex(info.tokenIn);
        uint8 j = IPoolSaddle(info.pool).getTokenIndex(info.tokenOut);

        // // console.log("i", i);
        // // console.log("j", j);
        uint256 amountOut = IPoolSaddle(info.pool).calculateSwap(
            i,
            j,
            amountIn
        );
        // // console.log("amountOut", amountOut);
        approveToken(info.tokenIn, info.pool);

        IPoolSaddle(info.pool).swap(i, j, amountIn, amountOut, block.timestamp);

        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapCurve(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("\n*********** SwapCurve ***********");
        // tokensBalance(info.tokenIn, info.tokenOut);

        uint256 i = 1000;
        uint256 j = 1000;

        for (uint k = 0; k < 20; k++) {
            if (i != 1000 && j != 1000) {
                break;
            }
            address coin = IPoolCurve(info.pool).coins(k);

            if (coin == info.tokenIn) {
                i = k;
            }
            if (coin == info.tokenOut) {
                j = k;
            }
        }

        approveToken(info.tokenIn, info.pool);
        uint256 dy = IPoolCurve(info.pool).get_dy(i, j, amountIn);

        IPoolCurve(info.pool).exchange(i, j, amountIn, dy);
        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    function SwapBalancer(SwapInfo memory info, uint256 amountIn) internal {
        // console.log("*********** SwapBalancer ***********");
        // tokensBalance(info.tokenIn, info.tokenOut);

        IBalancerVault.FundManagement memory fund = IBalancerVault
            .FundManagement(
                address(this),
                false,
                payable(address(this)),
                false
            );

        IBalancerVault.SingleSwap memory singleBalSwap = IBalancerVault
            .SingleSwap(
                info.poolId,
                IBalancerVault.SwapKind.GIVEN_IN,
                IAsset(info.tokenIn),
                IAsset(info.tokenOut),
                amountIn,
                ""
            );

        approveToken(info.tokenIn, info.pool);

        IBalancerVault(info.pool).swap(singleBalSwap, fund, 0, block.timestamp);
        // tokensBalance(info.tokenIn, info.tokenOut);
    }

    //IPoolKyberswapV2
    function swapCallback(
        int256 deltaQty0,
        int256 deltaQty1,
        bytes calldata
    ) external {
        int256 amount;
        IPoolKyberswapV2 pool = IPoolKyberswapV2(msg.sender);

        // tokensBalance(
        // 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270,
        // 0x1C954E8fe737F99f68Fa1CCda3e51ebDB291948C
        // );
        if (deltaQty0 > 0) {
            amount = deltaQty0;
            IERC20(pool.token0()).transfer(msg.sender, uint256(amount));
        } else {
            amount = deltaQty1;
            IERC20(pool.token1()).transfer(msg.sender, uint256(amount));
        }
    }

    // function tokensBalance(address tokenIn, address tokenOut) internal view {
    // uint256 balanceIn = IERC20(tokenIn).balanceOf(address(this));
    // uint256 balanceOut = IERC20(tokenOut).balanceOf(address(this));
    // console.log("\nbalance tokenIn", balanceIn, tokenIn);
    // console.log("balance tokenOut", balanceOut, tokenOut);
    // }

    function approveToken(address token, address pool) internal {
        if (IERC20(token).allowance(address(this), pool) == 0) {
            IERC20(token).approve(pool, MAX_INT);
        }
    }
}

