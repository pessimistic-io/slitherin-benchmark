// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {     MetaStable2TokenAuraStrategyContext,     StableOracleContext,     Balancer2TokenPoolContext } from "./BalancerVaultTypes.sol";
import {     StrategyContext,     StrategyVaultSettings,     StrategyVaultState,     TwoTokenPoolContext,     DepositParams,     RedeemParams,     ReinvestRewardParams } from "./VaultTypes.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {SettlementUtils} from "./SettlementUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";
import {Balancer2TokenPoolUtils} from "./Balancer2TokenPoolUtils.sol";
import {Stable2TokenOracleMath} from "./Stable2TokenOracleMath.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {Constants} from "./Constants.sol";
import {TypeConvert} from "./TypeConvert.sol";
import {IERC20} from "./interfaces_IERC20.sol";

library MetaStable2TokenAuraHelper {
    using Balancer2TokenPoolUtils for Balancer2TokenPoolContext;
    using Balancer2TokenPoolUtils for TwoTokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using Stable2TokenOracleMath for StableOracleContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;
    using TypeConvert for uint256;

    function deposit(
        MetaStable2TokenAuraStrategyContext memory context,
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
        MetaStable2TokenAuraStrategyContext memory context,
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
        MetaStable2TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );
        bool isSingleSidedExit = params.secondaryTradeParams.length == 0;

        uint256 bptToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.poolContext.basePool.poolToken.totalSupply()
        });

        uint256 oraclePrice = context.poolContext.basePool._getOraclePairPrice(context.baseStrategy);

        /// @notice params.minPrimary and params.minSecondary are not required to be passed in by the caller
        /// for this strategy vault
        (uint256 minPrimary, uint256 minSecondary) = context.oracleContext._getMinExitAmounts({
            poolContext: context.poolContext,
            strategyContext: context.baseStrategy,
            oraclePrice: oraclePrice,
            bptAmount: bptToSettle
        });

        context.poolContext._unstakeAndExitPool(
            context.stakingContext, bptToSettle, minPrimary, minSecondary, isSingleSidedExit
        );

        context.baseStrategy.vaultState.totalPoolClaim -= bptToSettle;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        emit VaultEvents.EmergencyVaultSettlement(maturity, bptToSettle, 0);
    }

    function reinvestReward(
        MetaStable2TokenAuraStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external returns (
        address rewardToken,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 poolClaimAmount
    ) {
        StrategyContext memory strategyContext = context.baseStrategy;
        Balancer2TokenPoolContext calldata poolContext = context.poolContext; 
        StableOracleContext calldata oracleContext = context.oracleContext;

        (
            rewardToken, 
            primaryAmount, 
            secondaryAmount
        ) = poolContext.basePool._executeRewardTrades({
            strategyContext: strategyContext,
            rewardTokens: context.stakingContext.rewardTokens,
            data: params.tradeData
        });

        // Make sure we are joining with the right proportion to minimize slippage
        oracleContext._validateSpotPriceAndPairPrice({
            poolContext: poolContext,
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
            /// @notice minBPT is not required to be set by the caller because primaryAmount
            /// and secondaryAmount are already validated
            minBPT: params.minPoolClaim      
        });

        strategyContext.vaultState.totalPoolClaim += poolClaimAmount;
        strategyContext.vaultState.setStrategyVaultState(); 

        emit VaultEvents.RewardReinvested(rewardToken, primaryAmount, secondaryAmount, poolClaimAmount); 
    }

    function getExchangeRate(MetaStable2TokenAuraStrategyContext calldata context) 
        external view returns (int256) {
        if (context.baseStrategy.vaultState.totalVaultSharesGlobal == 0) {
            return context.poolContext._getTimeWeightedPrimaryBalance({
                oracleContext: context.oracleContext,
                strategyContext: context.baseStrategy,
                bptAmount: context.baseStrategy.poolClaimPrecision // 1 pool token
            }).toInt();
        } else {
            return context.poolContext._convertStrategyToUnderlying({
                strategyContext: context.baseStrategy,
                oracleContext: context.oracleContext,
                strategyTokenAmount: uint256(Constants.INTERNAL_TOKEN_PRECISION) // 1 vault share
            });
        }
    }
}

