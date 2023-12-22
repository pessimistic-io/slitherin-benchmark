// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { ISiloStrategy, ISiloIncentiveController, ISiloRepository } from "./ISiloStrategy.sol";
import { ICamelot } from "./ICamelot.sol";
import { IFlashLoans } from "./IFlashLoans.sol";

error INVALID_TOKEN();
error NOT_SELF();

library SiloReward {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public constant uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // Silo
    address public constant provider = 0x8658047e48CC09161f4152c79155Dac1d710Ff0a; //Silo Repository
    address public constant siloIncentive = 0x4999873bF8741bfFFB0ec242AAaA7EF1FE74FCE8; // Silo Incenctive
    address public constant siloIncentiveSTIP = 0xd592F705bDC8C1B439Bd4D665Ed99C4FaAd5A680; // Silo STIP ARB

    address public constant siloToken = 0x0341C0C0ec423328621788d4854119B97f44E391; // Silo Token
    address public constant arb = 0x912CE59144191C1204E64559FE8253a0e49E6548; // Arb Token

    // Camelot
    address public constant camelotRouter = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    // WETH
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /// @notice Claims the specified reward token from the given incentive contract and charges a fee.
    /// @param incentiveContractAddress The address of the incentive contract to claim rewards from.
    /// @param rewardToken The token address of the reward to be claimed.
    /// @param fee The fee percentage to be charged on the claimed rewards.
    /// @param feeScale The scale to calculate the actual fee amount (typically 10000 for percentages).
    /// @param recipient The address receiving the fee.
    /// @return The net amount of reward tokens claimed after deducting the fee.
    function claimReward(
        address incentiveContractAddress,
        address rewardToken,
        uint256 fee,
        uint256 feeScale,
        address recipient
    ) public returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = rewardToken;
        ISiloIncentiveController(incentiveContractAddress).claimRewards(assets, type(uint256).max, address(this));

        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, rewardToken, fee, feeScale, recipient);
        IERC20(rewardToken).safeTransfer(msg.sender, balance - feeCharge);

        return balance - feeCharge;
    }

    /// @notice Claims rewards, swaps them to a specified asset, and then supplies the asset to a pool.
    /// @param incentiveContractAddress The address of the incentive contract to claim rewards from.
    /// @param rewardToken The token address of the reward to be claimed.
    /// @param asset The asset token to swap the rewards into and supply to the pool.
    /// @param fee The fee percentage to be charged on the claimed rewards.
    /// @param feeScale The scale to calculate the actual fee amount.
    /// @param recipient The address receiving the fee.
    /// @param amountOutMin The minimum amount expected from the swap operation.
    /// @param poolAddress The address of the pool where the asset will be supplied.
    /// @return The net amount of reward tokens claimed after the swap and fee deduction.
    function claimRewardsSupply(
        address incentiveContractAddress,
        address rewardToken,
        address asset,
        uint256 fee,
        uint256 feeScale,
        address recipient,
        uint256 amountOutMin,
        address poolAddress
    ) public returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = rewardToken;
        ISiloIncentiveController(incentiveContractAddress).claimRewards(assets, type(uint256).max, address(this));

        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, rewardToken, fee, feeScale, recipient);
        uint256 netBalance = balance - feeCharge;

        if (netBalance > 0) {
            // Swap to asset
            IERC20(rewardToken).approve(camelotRouter, netBalance);
            swapToken(rewardToken, asset, netBalance, amountOutMin);

            // Supply
            IERC20(asset).approve(poolAddress, IERC20(asset).balanceOf(address(this)));
            ISiloStrategy(poolAddress).deposit(asset, IERC20(asset).balanceOf(address(this)), false);
        }
        return netBalance;
    }

    /// @notice Claims rewards, swaps them to a specified debt token, and then uses them to repay debt.
    /// @param incentiveContractAddress The address of the incentive contract to claim rewards from.
    /// @param rewardToken The token address of the reward to be claimed.
    /// @param debtToken The debt token to swap the rewards into for repayment.
    /// @param fee The fee percentage to be charged on the claimed rewards.
    /// @param feeScale The scale to calculate the actual fee amount.
    /// @param recipient The address receiving the fee.
    /// @param amountOutMin The minimum amount expected from the swap operation.
    /// @param poolAddress The address of the pool where the debt will be repaid.
    /// @return The net amount of reward tokens claimed after the swap and fee deduction.
    function claimRewardsRepay(
        address incentiveContractAddress,
        address rewardToken,
        address debtToken,
        uint256 fee,
        uint256 feeScale,
        address recipient,
        uint256 amountOutMin,
        address poolAddress
    ) public returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = rewardToken;
        ISiloIncentiveController(incentiveContractAddress).claimRewards(assets, type(uint256).max, address(this));

        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, rewardToken, fee, feeScale, recipient);
        uint256 netBalance = balance - feeCharge;

        if (netBalance > 0) {
            // Swap to debtToken
            IERC20(rewardToken).approve(camelotRouter, netBalance);
            swapToken(rewardToken, debtToken, netBalance, amountOutMin);

            // Repay
            uint256 amount = IERC20(debtToken).balanceOf(address(this));
            IERC20(debtToken).approve(poolAddress, amount);
            ISiloStrategy(poolAddress).repay(debtToken, amount);
        }
        return netBalance;
    }

    /// @notice Calculates and transfers a fee based on the specified parameters.
    /// @dev This function is internal and used to handle fee deductions for various reward claiming operations.
    /// @param amount The total amount from which the fee is to be calculated.
    /// @param token The address of the token on which the fee is being charged.
    /// @param fee The fee percentage to be charged.
    /// @param feeScale The scale used for fee calculation, typically a value like 10000 for percentages.
    /// @param recipient The address that will receive the fee.
    /// @return depositFeeAmount The calculated fee amount that has been transferred to the recipient.
    function rewardFeeCharge(
        uint256 amount,
        address token,
        uint256 fee,
        uint256 feeScale,
        address recipient
    ) internal returns (uint256) {
        uint256 depositFeeAmount = amount.mul(fee).div(feeScale);
        IERC20(token).safeTransfer(recipient, depositFeeAmount);
        return depositFeeAmount;
    }

    /**
     * @notice Swaps tokens using the provided path.
     * @param _tokenIn The address of the input token.
     * @param _tokenOut The address of the output token.
     * @param _amountIn The amount of input tokens to be swapped.
     * @param _amountOutMin The minimum amount of out tokens to be swapped.
     */
    function swapToken(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _amountOutMin) internal {
        address[] memory path;

        if (_tokenOut == weth) {
            path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _tokenOut;
        } else {
            path = new address[](3);
            path[0] = _tokenIn;
            path[1] = weth;
            path[2] = _tokenOut;
        }

        ICamelot(camelotRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            _amountOutMin,
            path,
            address(this),
            address(0),
            block.timestamp
        );
    }

    // =============================================================
    //                 Helpers
    // =============================================================

    function toAmountRoundUp(uint256 share, uint256 totalAmount, uint256 totalShares) internal pure returns (uint256) {
        if (totalShares == 0 || totalAmount == 0) {
            return 0;
        }

        uint256 numerator = share * totalAmount;
        uint256 result = numerator / totalShares;

        // Round up
        if (numerator % totalShares != 0) {
            result += 1;
        }

        return result;
    }

    // =============================================================
    //                  Supply, Borrow, Repay, Withdraw
    // =============================================================

    function supply(address asset, uint256 amount, address poolAddress) public returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // supply
        IERC20(asset).approve(poolAddress, amount);
        ISiloStrategy(poolAddress).deposit(asset, amount, false);

        return amount;
    }

    function borrow(address debtToken, uint256 amount, address poolAddress) public returns (uint256) {
        ISiloStrategy(poolAddress).borrow(debtToken, amount);
        IERC20(debtToken).transfer(msg.sender, amount);
        return amount;
    }

    function repay(address debtToken, uint256 amount, address poolAddress) public returns (uint256) {
        IERC20(debtToken).transferFrom(msg.sender, address(this), amount);

        IERC20(debtToken).approve(poolAddress, amount);
        ISiloStrategy(poolAddress).repay(debtToken, amount);

        return amount;
    }

    function withdraw(address asset, address assetPool, uint256 amount, address poolAddress) public returns (uint256) {
        IERC20(assetPool).approve(poolAddress, amount);
        ISiloStrategy(poolAddress).withdraw(asset, amount, false);
        IERC20(asset).transfer(msg.sender, amount);

        return amount;
    }

    function withdrawTokenInCaseStuck(
        address tokenAddress,
        uint256 amount,
        address assetPool,
        address debtPool
    ) public returns (address, uint256) {
        if (tokenAddress == assetPool || tokenAddress == debtPool) revert INVALID_TOKEN();
        IERC20(tokenAddress).safeTransfer(msg.sender, amount);

        return (tokenAddress, amount);
    }
}

