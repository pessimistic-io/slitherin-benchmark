// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { ISwapHop, IStakingRewards } from "./Interfaces.sol";
import { DefinitiveAssets, IERC20 } from "./DefinitiveAssets.sol";
import { InputGreaterThanStaked } from "./DefinitiveErrors.sol";
import {     CoreAccessControlConfig,     CoreSwapConfig,     CoreFeesConfig,     LPStakingConfig,     LPStakingStrategy } from "./LPStakingStrategy.sol";
import { BaseTransfers } from "./BaseTransfers.sol";

contract HopStrategy is LPStakingStrategy, BaseTransfers {
    using DefinitiveAssets for IERC20;

    constructor(
        CoreAccessControlConfig memory coreAccessControlConfig,
        CoreSwapConfig memory coreSwapConfig,
        CoreFeesConfig memory coreFeesConfig,
        LPStakingConfig memory lpConfig
    ) LPStakingStrategy(coreAccessControlConfig, coreSwapConfig, coreFeesConfig, lpConfig) {}

    function _addLiquidity(uint256[] calldata amounts, uint256 minAmount) internal override {
        uint256 mLP_UNDERLYING_TOKENS_COUNT = LP_UNDERLYING_TOKENS_COUNT;
        address mLP_DEPOSIT_POOL = LP_DEPOSIT_POOL;
        address[] memory mLP_UNDERLYING_TOKENS = LP_UNDERLYING_TOKENS;
        for (uint256 i; i < mLP_UNDERLYING_TOKENS_COUNT; ) {
            DefinitiveAssets.validateBalance(mLP_UNDERLYING_TOKENS[i], amounts[i]);
            IERC20(mLP_UNDERLYING_TOKENS[i]).resetAndSafeIncreaseAllowance(address(this), mLP_DEPOSIT_POOL, amounts[i]);
            unchecked {
                ++i;
            }
        }
        //slither-disable-next-line unused-return
        ISwapHop(mLP_DEPOSIT_POOL).addLiquidity(amounts, minAmount, block.timestamp);
    }

    function _removeLiquidity(uint256 lpTokenAmount, uint256[] calldata minAmounts) internal override {
        address mLP_DEPOSIT_POOL = LP_DEPOSIT_POOL;
        DefinitiveAssets.validateBalance(LP_TOKEN, lpTokenAmount);
        IERC20(LP_TOKEN).resetAndSafeIncreaseAllowance(address(this), mLP_DEPOSIT_POOL, lpTokenAmount);

        //slither-disable-next-line unused-return
        ISwapHop(mLP_DEPOSIT_POOL).removeLiquidity(lpTokenAmount, minAmounts, block.timestamp);
    }

    function _removeLiquidityOneCoin(uint256 lpTokenAmount, uint256 minAmount, uint8 index) internal override {
        address mLP_TOKEN = LP_TOKEN;
        address mLP_DEPOSIT_POOL = LP_DEPOSIT_POOL;

        DefinitiveAssets.validateBalance(mLP_TOKEN, lpTokenAmount);
        IERC20(mLP_TOKEN).resetAndSafeIncreaseAllowance(address(this), mLP_DEPOSIT_POOL, lpTokenAmount);

        //slither-disable-next-line unused-return
        ISwapHop(mLP_DEPOSIT_POOL).removeLiquidityOneToken(lpTokenAmount, index, minAmount, block.timestamp);
    }

    function _stake(uint256 amount) internal override {
        address mLP_TOKEN = LP_TOKEN;
        address mLP_STAKING = LP_STAKING;
        DefinitiveAssets.validateBalance(mLP_TOKEN, amount);
        IERC20(mLP_TOKEN).resetAndSafeIncreaseAllowance(address(this), mLP_STAKING, amount);
        IStakingRewards(mLP_STAKING).stake(amount);
    }

    function _unstake(uint256 amount) internal override {
        if (_getAmountStaked() < amount) {
            revert InputGreaterThanStaked();
        }
        IStakingRewards(LP_STAKING).withdraw(amount);
    }

    function _getAmountStaked() internal view override returns (uint256 amount) {
        return IStakingRewards(LP_STAKING).balanceOf(address(this));
    }

    function _enter(uint256[] calldata amounts, uint256 minAmount) internal override returns (uint256 stakedAmount) {
        _addLiquidity(amounts, minAmount);
        stakedAmount = DefinitiveAssets.getBalance(LP_TOKEN);
        _stake(stakedAmount);
    }

    /**
     * @notice ExitOne Implementation - Unstake LP tokens, and remove liquidity to one asset
     * @dev Protocol does not claim when unstaking, need to manually claim
     */
    function _exitOne(uint256 lpTokenAmount, uint256 minAmount, uint8 index) internal override {
        _unstake(lpTokenAmount);
        _removeLiquidityOneCoin(lpTokenAmount, minAmount, index);
    }

    /**
     * @notice Exit Implementation - Unstake LP tokens, and remove liquidity to one asset
     * @dev Protocol does not claim when unstaking, need to manually claim
     */
    function _exit(uint256 lpTokenAmount, uint256[] calldata minAmounts) internal override {
        _unstake(lpTokenAmount);
        _removeLiquidity(lpTokenAmount, minAmounts);
    }

    function unclaimedRewards()
        public
        view
        override
        returns (IERC20[] memory rewardTokens, uint256[] memory earnedAmounts)
    {
        address mLP_STAKING = LP_STAKING;
        rewardTokens = new IERC20[](1);
        rewardTokens[0] = IStakingRewards(mLP_STAKING).rewardsToken();

        earnedAmounts = new uint256[](1);
        earnedAmounts[0] = IStakingRewards(mLP_STAKING).earned(address(this));
    }

    function _claimAllRewards()
        internal
        override
        returns (IERC20[] memory rewardTokens, uint256[] memory earnedAmounts)
    {
        (rewardTokens, earnedAmounts) = unclaimedRewards();
        IStakingRewards(LP_STAKING).getReward();
    }
}

