// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {     StrategyContext,      StrategyVaultSettings,      TradeParams,      TwoTokenPoolContext } from "./VaultTypes.sol";
import {ITradingModule, Trade, TradeType} from "./ITradingModule.sol";
import {ICurveGauge} from "./ICurveGauge.sol";
import {ICurvePool} from "./ICurvePool.sol";
import {IConvexBooster} from "./IConvexBooster.sol";
import {IERC20} from "./interfaces_IERC20.sol";

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    address pool;
    ITradingModule tradingModule;
    bool isSelfLPToken;
    uint32 settlementPeriodInSeconds;
}

struct ConvexVaultDeploymentParams {
    address rewardPool;
    DeploymentParams baseParams;
}

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
}

struct Curve2TokenPoolContext {
    TwoTokenPoolContext basePool;
    address curvePool;
    bool isV2;
}

struct ConvexStakingContext {
    address booster;
    address rewardPool;
    uint256 poolId;
    IERC20[] rewardTokens;
}

struct Curve2TokenConvexStrategyContext {
    StrategyContext baseStrategy;
    Curve2TokenPoolContext poolContext;
    ConvexStakingContext stakingContext;
}

