// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {     ConvexVaultDeploymentParams,      InitParams,      Curve2TokenPoolContext,     Curve2TokenConvexStrategyContext } from "./CurveVaultTypes.sol";
import {     StrategyContext,     StrategyVaultState,     StrategyVaultSettings,     RedeemParams,     DepositParams,     ReinvestRewardParams } from "./VaultTypes.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {Errors} from "./Errors.sol";
import {Constants} from "./Constants.sol";
import {TypeConvert} from "./TypeConvert.sol";
import {Deployments} from "./Deployments.sol";
import {TokenUtils, IERC20} from "./TokenUtils.sol";
import {Curve2TokenVaultMixin} from "./Curve2TokenVaultMixin.sol";
import {Curve2TokenPoolUtils} from "./Curve2TokenPoolUtils.sol";
import {Curve2TokenConvexHelper} from "./Curve2TokenConvexHelper.sol";
import {NotionalProxy} from "./NotionalProxy.sol";
import {SettlementUtils} from "./SettlementUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";

contract Curve2TokenConvexVault is Curve2TokenVaultMixin {
    using TypeConvert for uint256;
    using TypeConvert for int256;
    using TokenUtils for IERC20;
    using SettlementUtils for StrategyContext;
    using VaultStorage for StrategyVaultState;
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using Curve2TokenConvexHelper for Curve2TokenConvexStrategyContext;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        Curve2TokenVaultMixin(notional_, params) {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("Curve2TokenConvexVault"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);        
        VaultStorage.setStrategyVaultSettings(params.settings);

        if (PRIMARY_TOKEN != Deployments.ALT_ETH_ADDRESS) {
            IERC20(PRIMARY_TOKEN).checkApprove(address(CURVE_POOL), type(uint256).max);
        }
        if (SECONDARY_TOKEN != Deployments.ALT_ETH_ADDRESS) {
            IERC20(SECONDARY_TOKEN).checkApprove(address(CURVE_POOL), type(uint256).max);
        }

        CURVE_POOL_TOKEN.checkApprove(address(CONVEX_BOOSTER), type(uint256).max);
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        strategyTokensMinted = _strategyContext().deposit(deposit, data);
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {
        finalPrimaryBalance = _strategyContext().redeem(strategyTokens, data);
    }   

    function settleVaultEmergency(uint256 maturity, bytes calldata data) 
        external onlyRole(EMERGENCY_SETTLEMENT_ROLE) {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);
        Curve2TokenConvexHelper.settleVaultEmergency(
            _strategyContext(), maturity, data
        );
        _lockVault();
    }

    function restoreVault(uint256 minPoolClaim) external whenLocked onlyNotionalOwner {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();

        uint256 poolClaimAmount = context.poolContext._joinPoolAndStake({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            primaryAmount: TokenUtils.tokenBalance(PRIMARY_TOKEN),
            secondaryAmount: TokenUtils.tokenBalance(SECONDARY_TOKEN),
            minPoolClaim: minPoolClaim
        });

        context.baseStrategy.vaultState.totalPoolClaim += poolClaimAmount;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        _unlockVault();
    }

    function getEmergencySettlementPoolClaimAmount(uint256 maturity) external view returns (uint256 poolClaimToSettle) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        poolClaimToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.poolContext.basePool.poolToken.totalSupply()
        });
    }

    function reinvestReward(ReinvestRewardParams calldata params) 
        external onlyRole(REWARD_REINVESTMENT_ROLE) {
        Curve2TokenConvexHelper.reinvestReward(_strategyContext(), params);        
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view virtual override returns (int256 underlyingValue) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        (uint256 spotPrice, uint256 oraclePrice) = context.poolContext._getSpotPriceAndOraclePrice(context.baseStrategy);
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            strategyTokenAmount: strategyTokenAmount,
            oraclePrice: oraclePrice,
            spotPrice: spotPrice
        });
    } 

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPrice) {
        spotPrice = _strategyContext().poolContext._getSpotPrice(tokenIndex);
    }

    function getStrategyContext() external view returns (Curve2TokenConvexStrategyContext memory) {
        return _strategyContext();
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        VaultStorage.setStrategyVaultSettings(settings);
    }
}

