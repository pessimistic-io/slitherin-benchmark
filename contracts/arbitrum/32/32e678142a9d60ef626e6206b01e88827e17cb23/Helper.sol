// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./console.sol";

import "./IHelper.sol";
import "./HelperUtils.sol";

import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeMath.sol";
import {SafeCast as SafeCastOZ } from "./libraries_SafeCast.sol";

import "./TickMath.sol";
import "./FullMath.sol";
import "./IUniswapV3Factory.sol";

import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./LiquidityAmounts.sol";
import "./INonfungiblePositionManager.sol";

import "./AggregatorV3Interface.sol";

import "./IAaveOracle.sol";

contract Helper is IHelper {

    using SafeMath for uint256;

    IAaveOracle immutable oracle;
    ISwapRouter immutable swapRouter;
    IUniswapV3Factory immutable uniswapFactory;
    INonfungiblePositionManager immutable nonfungiblePositionManager;

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        IUniswapV3Factory _uniswapFactory,
        ISwapRouter _swapRouter,
        IAaveOracle _oracle
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        uniswapFactory = _uniswapFactory;
        swapRouter = _swapRouter;
        oracle = _oracle;
    }

    /**
     *  @inheritdoc IHelper
     */
    function mintPosition(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint24 poolFee,
        int24 tickLower,
        int24 tickUpper,
        uint24 slippage
    ) external override {
        require(tokenA != tokenB,"Helper: TokenA and TokenB cannot be the same");
        require(ERC20(tokenA).allowance(msg.sender,address(this))>=amountA, "Helper: Insuficient allowance");
        TransferHelper.safeTransferFrom(address(tokenA),msg.sender, address(this), amountA);

        //To avoid stack too deep
        MintPositionInternalParams memory params;

        params.tokenADecimals = ERC20(tokenA).decimals();
        params.tokenBDecimals = ERC20(tokenB).decimals();
        //1 tokenB = tokenBPrice of token A
         params.tokenBPrice = HelperUtils.getTokenPrice(address(tokenA), params.tokenADecimals, address(tokenB), params.tokenBDecimals, false, oracle);

        (params.sqrtPriceX96, params.tick, params.token0, params.token1, params.poolFee) = HelperUtils.getPoolInfo(address(tokenA), address(tokenB), poolFee, uniswapFactory);

        uint256 amountAToSwap = HelperUtils.computeAmount(HelperUtils.ComputeAmountParams(
            address(tokenA),
            amountA,
            params.tokenADecimals,
            params.tokenBDecimals,
            params.tokenBPrice,
            tickLower,
            tickUpper,
            params.sqrtPriceX96,
            params.tick,
            params.token0
        ));

        console.log("Amount A to Swap", amountAToSwap);
        if(params.token0==address(tokenA)){
            params.amount0 = ERC20(tokenA).balanceOf(address(this));
            params.amount1 = _swap(address(tokenA),amountAToSwap,address(tokenB),params.tokenBPrice,params.tokenBDecimals,slippage,params.poolFee);
        } else {
            params.amount0 = _swap(address(tokenA),amountAToSwap,address(tokenB),params.tokenBPrice,params.tokenBDecimals,slippage,params.poolFee);
            params.amount1 = ERC20(tokenA).balanceOf(address(this));
        }

        (uint256 tokenId, uint128 liquidity , uint256 amount0, uint256 amount1) = _mintUniswapPosition(
            params.token0, 
            params.amount0, 
            params.token1,
            params.amount1, 
            params.poolFee, 
            tickLower, 
            tickUpper
        );

        emit MintUniswapPosition(msg.sender, tokenId, liquidity, amount0, amount1 );

    }

    /**
     * @notice Mints a liquidity position in Uniswap by providing specified amounts of token0 and token1.
     * 
     * @param token0 The address of token0.
     * @param amount0ToMint The amount of token0 to be minted.
     * @param token1 The address of token1.
     * @param amount1ToMint The amount of token1 to be minted.
     * @param fee The fee of the pool in which the position is minted.
     * @param lowerTick The lower tick of the position range.
     * @param upperTick The upper tick of the position range.
     *
     * @dev The contract must own the amount0ToMint and amount1ToMint
     */
    function _mintUniswapPosition(
        address token0, 
        uint256 amount0ToMint, 
        address token1, 
        uint256 amount1ToMint, 
        uint24 fee, 
        int24 lowerTick, 
        int24 upperTick 
    ) internal returns (uint256 tokenId, uint128 liquidity , uint256 amount0, uint256 amount1) {

        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amount1ToMint);

        INonfungiblePositionManager.MintParams memory paramsMint = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: lowerTick,
            tickUpper: upperTick,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp
        });

        (tokenId, liquidity , amount0, amount1) = nonfungiblePositionManager.mint(paramsMint);

         // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(token0, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(token1, msg.sender, refund1);
        }

        console.log('TokenId: {}, Amount0: {}, Amount1: {} ',tokenId, amount0, amount1);
    }


    function _swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 tokenOutPrice,
        uint8 tokenOutDecimals,
        uint24 slippage,
        uint24 poolFee
    ) internal returns (uint256 amountOut) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: HelperUtils.computeAmountMin( amountIn, tokenOutPrice, tokenOutDecimals, poolFee, slippage),
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);

    }

    /**
     *  @inheritdoc IHelper
     */
    function swap( address tokenIn, uint256 amountIn, address tokenOut, uint24 slippage, uint24 poolFee) external override {
        require(tokenIn != tokenOut,"Helper: TokenIn and TokenOut cannot be the same");
        require(ERC20(tokenIn).allowance(msg.sender,address(this))>=amountIn, "Helper: Insuficient allowance");
        TransferHelper.safeTransferFrom(address(tokenIn),msg.sender, address(this), amountIn);

        uint8 tokenInDecimals = ERC20(tokenIn).decimals();
        uint8 tokenOutDecimals = ERC20(tokenOut).decimals();
        
        //1 tokenOut = tokenOutPrice of tokenIn
        uint256 tokenOutPrice = HelperUtils.getTokenPrice(address(tokenIn), tokenInDecimals, address(tokenOut), tokenOutDecimals, false, oracle);

        uint256 amountOut = _swap(tokenIn, amountIn,tokenOut,tokenOutPrice,tokenOutDecimals,slippage,poolFee);

        TransferHelper.safeTransfer(tokenOut, msg.sender, amountOut);
    
        emit SwapUniswap(msg.sender, tokenIn, amountIn, tokenOut, amountOut, tokenOutPrice);
    }

}

