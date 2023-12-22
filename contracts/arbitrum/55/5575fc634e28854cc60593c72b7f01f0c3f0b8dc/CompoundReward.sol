// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { ICometRewards, IComet } from "./ICompound.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { SafeMath } from "./SafeMath.sol";

library CompoundReward {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public constant uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant cometReward = 0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;
    address public constant comet = 0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA;
    address public constant compoundToken = 0x354A6dA3fcde098F8389cad84b0182725c6C91dE;

    function claimReward(uint256 fee, uint256 feeScale, address recipient) public returns (uint256) {
        ICometRewards(cometReward).claim(comet, msg.sender, true);
        uint256 balance = IERC20(compoundToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, compoundToken, fee, feeScale, recipient);
        IERC20(compoundToken).safeTransfer(msg.sender, balance - feeCharge);
        return balance - feeCharge;
    }

    function claimRewardsSupply(address pool, address asset, uint256 fee, uint256 feeScale, address recipient, uint256 amountOutMinimum) public returns (uint256) {
        ICometRewards(cometReward).claim(comet, msg.sender, true);

        uint256 balance = IERC20(compoundToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, compoundToken, fee, feeScale, recipient);
        uint256 netBalance = balance - feeCharge;
        if (netBalance > 0) {
            swapToken(compoundToken, asset, netBalance, amountOutMinimum);
            IERC20(asset).approve(pool, IERC20(asset).balanceOf(address(this)));
            IComet(pool).supply(asset, IERC20(asset).balanceOf(address(this)));
        }
        return netBalance;
    }

    function claimRewardsRepay(address pool, address asset, uint256 fee, uint256 feeScale, address recipient, uint256 amountOutMinimum) public returns (uint256) {
        ICometRewards(cometReward).claim(comet, msg.sender, true);

        uint256 balance = IERC20(compoundToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, compoundToken, fee, feeScale, recipient);
        uint256 netBalance = balance - feeCharge;
        if (netBalance > 0) {
            swapToken(compoundToken, asset, netBalance, amountOutMinimum);
            IERC20(asset).approve(pool, IERC20(asset).balanceOf(address(this)));
            IComet(pool).supply(asset, IERC20(asset).balanceOf(address(this)));
        }
        return netBalance;
    }

     function rewardFeeCharge(uint256 amount, address token, uint256 fee, uint256 feeScale, address recipient) public returns (uint256) {
        uint256 depositFeeAmount = amount.mul(fee).div(feeScale);
        IERC20(token).safeTransfer(recipient, depositFeeAmount);
        return depositFeeAmount;
    }

    function swapToken(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 amountOutMinimum
    ) public returns (uint256) {
        TransferHelper.safeApprove(tokenIn, address(uniswapV3Router), amount);

        uint24 poolFee = 3000;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        return ISwapRouter(uniswapV3Router).exactInputSingle(params);
    }
}
