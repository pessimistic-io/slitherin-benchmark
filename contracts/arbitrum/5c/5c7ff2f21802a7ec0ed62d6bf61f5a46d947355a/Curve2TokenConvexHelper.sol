// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {     Curve2TokenConvexStrategyContext,     Curve2TokenPoolContext } from "./CurveVaultTypes.sol";
import {     StrategyContext,     StrategyVaultSettings,     StrategyVaultState,     TwoTokenPoolContext,     DepositParams,     RedeemParams,     ReinvestRewardParams } from "./VaultTypes.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";
import {SettlementUtils} from "./SettlementUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {VaultConstants} from "./VaultConstants.sol";
import {Curve2TokenPoolUtils} from "./Curve2TokenPoolUtils.sol";
import {IERC20} from "./interfaces_IERC20.sol";

library Curve2TokenConvexHelper {
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultStorage for StrategyVaultState;

    function deposit(
        Curve2TokenConvexStrategyContext memory context,
        uint256 deposit,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        strategyTokensMinted = context.poolContext._deposit({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            deposit: deposit,
            params: params
        });
    }

    function redeem(
        Curve2TokenConvexStrategyContext memory context,
        uint256 strategyTokens,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            strategyTokens: strategyTokens,
            params: params
        });
    }

    function settleVaultEmergency(
        Curve2TokenConvexStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );

        uint256 poolClaimToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.poolContext.basePool.poolToken.totalSupply()
        });

        context.poolContext._unstakeAndExitPool({
            stakingContext: context.stakingContext,
            poolClaim: poolClaimToSettle,
            params: params
        });

        context.baseStrategy.vaultState.totalPoolClaim -= poolClaimToSettle;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        emit VaultEvents.EmergencyVaultSettlement(maturity, poolClaimToSettle, 0);  
    }

    function reinvestReward(
        Curve2TokenConvexStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external returns (
        address rewardToken,
        uint256 amountSold,
        uint256 poolClaimAmount
    ) {
        StrategyContext memory strategyContext = context.baseStrategy;
        Curve2TokenPoolContext calldata poolContext = context.poolContext; 

        uint256 primaryAmount;
        uint256 secondaryAmount;
        (
            rewardToken, 
            amountSold,
            primaryAmount,
            secondaryAmount
        ) = poolContext.basePool._executeRewardTrades({
            strategyContext: strategyContext,
            rewardTokens: context.stakingContext.rewardTokens,
            data: params.tradeData
        });

        // Make sure we are joining with the right proportion to minimize slippage
        poolContext._validateSpotPriceAndPairPrice({
            strategyContext: strategyContext,
            oraclePrice: poolContext.basePool._getOraclePairPrice(strategyContext),
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount
        });

        poolClaimAmount = poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            stakingContext: context.stakingContext,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount,
            /// @notice minPoolClaim is not required to be set by the caller because primaryAmount
            /// and secondaryAmount are already validated
            minPoolClaim: params.minPoolClaim      
        });

        strategyContext.vaultState.totalPoolClaim += poolClaimAmount;
        strategyContext.vaultState.setStrategyVaultState(); 

        emit VaultEvents.RewardReinvested(rewardToken, amountSold, poolClaimAmount);
    }
}

