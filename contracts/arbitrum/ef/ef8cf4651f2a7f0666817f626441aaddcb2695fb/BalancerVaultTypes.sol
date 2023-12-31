// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {     StrategyContext,      StrategyVaultSettings,      TradeParams,     TwoTokenPoolContext,     ThreeTokenPoolContext } from "./VaultTypes.sol";
import {IStrategyVault} from "./IStrategyVault.sol";
import {VaultConfig} from "./IVaultController.sol";
import {IAuraBooster} from "./IAuraBooster.sol";
import {IAuraRewardPool} from "./IAuraRewardPool.sol";
import {NotionalProxy} from "./NotionalProxy.sol";
import {ILiquidityGauge} from "./ILiquidityGauge.sol";
import {IBalancerVault} from "./IBalancerVault.sol";
import {IBalancerMinter} from "./IBalancerMinter.sol";
import {ITradingModule, Trade, TradeType} from "./ITradingModule.sol";
import {IAsset} from "./IBalancerVault.sol";
import {IERC20} from "./interfaces_IERC20.sol";

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    bytes32 balancerPoolId;
    ILiquidityGauge liquidityGauge;
    ITradingModule tradingModule;
}

struct AuraVaultDeploymentParams {
    IAuraRewardPool rewardPool;
    DeploymentParams baseParams;
}

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
}

/// @notice Parameters for joining/exiting Balancer pools
struct PoolParams {
    IAsset[] assets;
    uint256[] amounts;
    uint256 msgValue;
    bytes customData;
}

struct StableOracleContext {
    /// @notice Amplification parameter
    uint256 ampParam;
}

struct UnderlyingPoolContext {
    uint256 mainScaleFactor;
    uint256 mainBalance;
    uint256 wrappedScaleFactor;
    uint256 wrappedBalance;
    uint256 virtualSupply;
    uint256 fee;
    uint256 lowerTarget;
    uint256 upperTarget;
}

struct BoostedOracleContext {
    /// @notice Amplification parameter
    uint256 ampParam;
    /// @notice BPT balance in the pool
    uint256 bptBalance;
    /// @notice Boosted pool swap fee
    uint256 swapFeePercentage;
    /// @notice Virtual supply
    uint256 virtualSupply;
    /// @notice Underlying linear pool for the primary token
    UnderlyingPoolContext[] underlyingPools;
}

struct AuraStakingContext {
    ILiquidityGauge liquidityGauge;
    address booster;
    IAuraRewardPool rewardPool;
    uint256 poolId;
    IERC20[] rewardTokens;
}

struct Balancer2TokenPoolContext {
    TwoTokenPoolContext basePool;
    uint256 primaryScaleFactor;
    uint256 secondaryScaleFactor;
    bytes32 poolId;
}

struct Balancer3TokenPoolContext {
    ThreeTokenPoolContext basePool;
    uint256 primaryScaleFactor;
    uint256 secondaryScaleFactor;
    uint256 tertiaryScaleFactor;
    bytes32 poolId;
}

struct MetaStable2TokenAuraStrategyContext {
    Balancer2TokenPoolContext poolContext;
    StableOracleContext oracleContext;
    AuraStakingContext stakingContext;
    StrategyContext baseStrategy;
}

struct Boosted3TokenAuraStrategyContext {
    Balancer3TokenPoolContext poolContext;
    BoostedOracleContext oracleContext;
    AuraStakingContext stakingContext;
    StrategyContext baseStrategy;
}

