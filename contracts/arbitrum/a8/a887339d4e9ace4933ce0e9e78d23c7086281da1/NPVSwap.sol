// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./console.sol";

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

import { YieldSlice } from "./YieldSlice.sol";
import { NPVToken } from "./NPVToken.sol";
import { ILiquidityPool } from "./ILiquidityPool.sol";

contract NPVSwap {
    using SafeERC20 for IERC20;

    NPVToken public immutable npvToken;
    YieldSlice public immutable slice;
    ILiquidityPool public immutable pool;

    constructor(address npvToken_, address slice_, address pool_) {
        require(npvToken_ == ILiquidityPool(pool_).token0() ||
                npvToken_ == ILiquidityPool(pool_).token1(), "NS: wrong token");

        npvToken = NPVToken(npvToken_);
        slice = YieldSlice(slice_);
        pool = ILiquidityPool(pool_);
    }


    // --------------------------------------------------------- //
    // ---- Low level: Transacting in NPV tokens and slices ---- //
    // --------------------------------------------------------- //
    function previewLockForNPV(uint256 tokens, uint256 yield) public view returns (uint256) {
        (uint256 npv, uint256 fees) = slice.previewDebtSlice(tokens, yield);
        return npv - fees;
    }

    function previewSwapYieldForNPV(uint256 yieldIn, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        return pool.previewSwap(address(slice.yieldToken()),
                                uint128(yieldIn),
                                sqrtPriceLimitX96);
    }

    function previewSwapYieldForNPVOut(uint256 npvOut, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        return pool.previewSwapOut(address(slice.yieldToken()),
                                   uint128(npvOut),
                                   sqrtPriceLimitX96);
    }

    function previewSwapNPVForYield(uint256 npvIn, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        return pool.previewSwap(address(npvToken),
                                uint128(npvIn),
                                sqrtPriceLimitX96);
    }

    function previewSwapNPVForYieldOut(uint256 yieldOut, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        return pool.previewSwapOut(address(npvToken),
                                   uint128(yieldOut),
                                   sqrtPriceLimitX96);
    }

    // Lock yield generating tokens for NPV tokens
    function lockForNPV(address owner,
                        address recipient,
                        uint256 tokens,
                        uint256 yield,
                        bytes calldata memo) public returns (uint256) {

        IERC20(slice.generatorToken()).safeTransferFrom(msg.sender, address(this), tokens);
        slice.generatorToken().safeApprove(address(slice), 0);
        slice.generatorToken().safeApprove(address(slice), tokens);

        uint256 id = slice.debtSlice(owner, recipient, tokens, yield, memo);

        return id;
    }

    // Swap NPV tokens for a future yield slice
    function swapNPVForSlice(uint256 npv, bytes calldata memo) public returns (uint256) {
        IERC20(slice.npvToken()).safeTransferFrom(msg.sender, address(this), npv);
        IERC20(slice.npvToken()).safeApprove(address(slice), 0); 
        IERC20(slice.npvToken()).safeApprove(address(slice), npv);

        uint256 id = slice.creditSlice(npv, msg.sender, memo);

        return id;
    }



    // --------------------------------------------------------------- //
    // ---- High level: Transacting in generator and yield tokens ---- //
    // --------------------------------------------------------------- //

    // Give a preview of `lockForYield`. Not a view, and should not be used
    // on-chain, due to underlying Uniswap v3 behavior.
    function previewLockForYield(uint256 tokens, uint256 yield, uint128 sqrtPriceLimitX96)
        public returns (uint256, uint256) {

        uint256 previewNPV = previewLockForNPV(tokens, yield);
        return pool.previewSwap(address(npvToken), uint128(previewNPV), sqrtPriceLimitX96);
    }

    function previewSwapForSlice(uint256 yieldIn, uint128 sqrtPriceLimitX96) public returns (uint256, uint256) {
        (uint256 npv, uint256 priceX96) = pool.previewSwap(address(slice.yieldToken()),
                                                           uint128(yieldIn),
                                                           sqrtPriceLimitX96);
        uint256 fees = slice.creditFeesForNPV(npv);
        return (npv - fees, priceX96);
    }

    // Lock and swap yield generating tokens for yield tokens
    function lockForYield(address owner,
                          uint256 tokens,
                          uint256 yield,
                          uint256 amountOutMin,
                          uint128 sqrtPriceLimitX96,
                          bytes calldata memo) public returns (uint256) {

        uint256 npv = previewLockForNPV(tokens, yield);
        lockForNPV(owner, address(this), tokens, yield, memo);
        IERC20(npvToken).safeApprove(address(pool), 0);
        IERC20(npvToken).safeApprove(address(pool), npv);
        return pool.swap(owner,
                         address(npvToken),
                         uint128(npv),
                         uint128(amountOutMin),
                         sqrtPriceLimitX96);
    }

    // Swap yield for future yield slice
    function swapForSlice(address recipient,
                          uint256 yield,
                          uint256 npvMin,
                          uint128 sqrtPriceLimitX96,
                          bytes calldata memo) public returns (uint256) {
        slice.yieldToken().safeTransferFrom(msg.sender, address(this), yield);
        slice.yieldToken().safeApprove(address(pool), 0);
        slice.yieldToken().safeApprove(address(pool), yield);

        uint256 out = pool.swap(address(this),
                                address(slice.yieldToken()),
                                uint128(yield),
                                uint128(npvMin),
                                sqrtPriceLimitX96);

        IERC20(slice.npvToken()).safeApprove(address(slice), 0);
        IERC20(slice.npvToken()).safeApprove(address(slice), out);
        uint256 id = slice.creditSlice(out, recipient, memo);

        return id;
    }

    // ----------------------------------------------------------------- //
    // ---- Repay with yield: Mint NPV with yield, and pay off debt ---- //
    // ----------------------------------------------------------------- //

    function mintAndPayWithYield(uint256 id, uint256 amount) public {

        slice.yieldToken().safeTransferFrom(msg.sender, address(this), amount);
        slice.yieldToken().safeApprove(address(slice), 0);
        slice.yieldToken().safeApprove(address(slice), amount);
        slice.mintFromYield(address(this), amount);
        IERC20(slice.npvToken()).safeApprove(address(slice), 0);
        IERC20(slice.npvToken()).safeApprove(address(slice), amount);
        uint256 paid = slice.payDebt(id, amount);
        if (paid != amount) {
            IERC20(slice.npvToken()).safeTransfer(msg.sender, amount - paid);
        }
    }
}

