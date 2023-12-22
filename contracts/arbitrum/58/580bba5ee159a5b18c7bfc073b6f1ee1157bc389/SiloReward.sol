// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { ICometRewards, IComet } from "./ICompound.sol";
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
    address public constant cometReward = 0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;
    address public constant comet = 0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA;
    address public constant compoundToken = 0x354A6dA3fcde098F8389cad84b0182725c6C91dE;

    // Silo
    address public constant provider = 0x8658047e48CC09161f4152c79155Dac1d710Ff0a; //Silo Repository
    address public constant siloIncentive = 0x4999873bF8741bfFFB0ec242AAaA7EF1FE74FCE8; // Silo Incenctive
    address public constant siloToken = 0x0341C0C0ec423328621788d4854119B97f44E391; // Silo Token

    // Camelot
    address public constant camelotRouter = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    // WETH
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function claimReward(uint256 fee, uint256 feeScale, address recipient) public returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = siloToken;
        ISiloIncentiveController(siloIncentive).claimRewards(assets, type(uint).max, address(this));
        uint256 balance = IERC20(siloToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, siloToken, fee, feeScale, recipient);
        IERC20(siloToken).safeTransfer(msg.sender, balance - feeCharge);
        return balance - feeCharge;
    }

    function claimRewardsSupply(
        address asset,
        uint256 fee,
        uint256 feeScale,
        address recipient,
        uint256 amountOutMin
    ) public returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = siloToken;
        ISiloIncentiveController(siloIncentive).claimRewards(assets, type(uint).max, address(this));

        uint256 balance = IERC20(siloToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, siloToken, fee, feeScale, recipient);
        uint256 netBalance = balance - feeCharge;

        if (netBalance > 0) {
            address poolAddress = ISiloRepository(provider).getSilo(asset);

            // swap to asset
            IERC20(siloToken).approve(camelotRouter, netBalance);
            swapToken(siloToken, asset, netBalance, amountOutMin);

            // supply
            IERC20(asset).approve(poolAddress, IERC20(asset).balanceOf(address(this)));
            ISiloStrategy(poolAddress).deposit(asset, IERC20(asset).balanceOf(address(this)), false);
        }
        return netBalance;
    }

    function claimRewardsRepay(
        address pool,
        address debtToken,
        uint256 fee,
        uint256 feeScale,
        address recipient,
        uint256 amountOutMin
    ) public returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = siloToken;
        ISiloIncentiveController(siloIncentive).claimRewards(assets, type(uint).max, address(this));

        uint256 balance = IERC20(siloToken).balanceOf(address(this));
        uint256 feeCharge = rewardFeeCharge(balance, siloToken, fee, feeScale, recipient);
        uint256 netBalance = balance - feeCharge;

        if (netBalance > 0) {
            address poolAddress = ISiloRepository(provider).getSilo(pool);

            //swap to debtToken
            IERC20(siloToken).approve(camelotRouter, netBalance);
            swapToken(siloToken, debtToken, netBalance, amountOutMin);

            // Repay
            uint256 amount = IERC20(debtToken).balanceOf(address(this));
            // uint256 repayAmount = amount > debtToken ? debtBalance() : amount;
            IERC20(debtToken).approve(poolAddress, amount);
            ISiloStrategy(poolAddress).repay(debtToken, amount);
        }
        return netBalance;
    }

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
    //                  Supply, Borrow, Repay, Withdraw
    // =============================================================

    function supply(address asset, uint256 amount) public returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // supply
        address poolAddress = ISiloRepository(provider).getSilo(asset);
        IERC20(asset).approve(poolAddress, amount);
        ISiloStrategy(poolAddress).deposit(asset, amount, false);

        return amount;
    }

    function borrow(address asset, address debtToken, uint256 amount) public returns (uint256) {
        address poolAddress = ISiloRepository(provider).getSilo(asset);
        ISiloStrategy(poolAddress).borrow(debtToken, amount);
        IERC20(debtToken).transfer(msg.sender, amount);
        return amount;
    }

    function repay(address asset, address debtToken, uint256 amount) public returns (uint256) {
        IERC20(debtToken).transferFrom(msg.sender, address(this), amount);

        address poolAddress = ISiloRepository(provider).getSilo(asset);
        IERC20(debtToken).approve(poolAddress, amount);
        ISiloStrategy(poolAddress).repay(debtToken, amount);

        return amount;
    }

    function withdraw(address asset, address assetPool, uint256 amount) public returns (uint256) {
        address poolAddress = ISiloRepository(provider).getSilo(asset);
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

