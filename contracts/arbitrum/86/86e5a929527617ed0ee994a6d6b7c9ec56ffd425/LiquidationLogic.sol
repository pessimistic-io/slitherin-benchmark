// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./FixedPointMathLib.sol";
import "./DataType.sol";
import "./Perp.sol";
import "./PositionCalculator.sol";
import "./DebtCalculator.sol";
import "./ScaledAsset.sol";
import "./TradeLogic.sol";

/*
 * Error Codes
 * L1: vault must be danger before liquidation
 * L2: vault must be (safe if there are positions) or (margin is negative if there are no positions) after liquidation
 * L3: too much slippage
 * L4: close ratio must be between 0 and 1e18
 */
library LiquidationLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event PositionLiquidated(
        uint256 vaultId, uint256 assetId, int256 tradeAmount, int256 tradeSqrtAmount, Perp.Payoff payoff, int256 fee
    );
    event VaultLiquidated(
        uint256 vaultId,
        uint256 mainVaultId,
        uint256 withdrawnMarginAmount,
        address liquidator,
        uint256 totalPenaltyAmount
    );

    function execLiquidationCall(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        DataType.Vault storage _mainVault,
        uint256 _closeRatio
    ) external returns (uint256 totalPenaltyAmount) {
        require(0 < _closeRatio && _closeRatio <= Constants.ONE, "L4");

        DataType.AssetStatus storage stableAssetStatus = _assets[Constants.STABLE_ASSET_ID];

        // The vault must be danger
        PositionCalculator.isDanger(_assets, _vault);

        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            DataType.UserStatus storage userStatus = _vault.openPositions[i];

            (int256 totalPayoff, uint256 penaltyAmount) =
                closePerp(_vault.id, _assets[userStatus.assetId], stableAssetStatus, userStatus.perpTrade, _closeRatio);

            _vault.margin += totalPayoff;
            totalPenaltyAmount += penaltyAmount;
        }

        (_vault.margin, totalPenaltyAmount) = calculatePayableReward(_vault.margin, totalPenaltyAmount);

        // The vault must be safe after liquidation call
        PositionCalculator.isSafe(_assets, _vault, true);

        int256 withdrawnMarginAmount;

        // If the vault is isolated and margin is not negative, the contract moves vault's margin to the main vault.
        if (_mainVault.id > 0 && _vault.id != _mainVault.id && _vault.margin > 0) {
            withdrawnMarginAmount = _vault.margin;

            _mainVault.margin += _vault.margin;

            _vault.margin = 0;
        }

        // withdrawnMarginAmount is always positive because it's checked in before lines
        emit VaultLiquidated(_vault.id, _mainVault.id, uint256(withdrawnMarginAmount), msg.sender, totalPenaltyAmount);
    }

    function calculatePayableReward(int256 reserveBefore, uint256 expectedReward)
        internal
        pure
        returns (int256 reserveAfter, uint256 payableReward)
    {
        if (reserveBefore >= int256(expectedReward)) {
            return (reserveBefore - int256(expectedReward), expectedReward);
        } else if (reserveBefore >= 0) {
            return (0, uint256(reserveBefore));
        } else {
            return (reserveBefore, 0);
        }
    }

    function closePerp(
        uint256 _vaultId,
        DataType.AssetStatus storage _underlyingAssetStatus,
        DataType.AssetStatus storage _stableAssetStatus,
        Perp.UserStatus storage _perpUserStatus,
        uint256 _closeRatio
    ) internal returns (int256 totalPayoff, uint256 penaltyAmount) {
        int256 tradeAmount = -_perpUserStatus.perp.amount * int256(_closeRatio) / int256(Constants.ONE);
        int256 tradeAmountSqrt = -_perpUserStatus.sqrtPerp.amount * int256(_closeRatio) / int256(Constants.ONE);

        uint160 sqrtTwap = UniHelper.getSqrtTWAP(_underlyingAssetStatus.sqrtAssetStatus.uniswapPool);
        uint256 debtValue = DebtCalculator.calculateDebtValue(_underlyingAssetStatus, _perpUserStatus, sqrtTwap);

        DataType.TradeResult memory tradeResult =
            TradeLogic.trade(_underlyingAssetStatus, _stableAssetStatus, _perpUserStatus, tradeAmount, tradeAmountSqrt);

        totalPayoff = tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        {
            // reverts if price is out of slippage threshold
            uint256 sqrtPrice = UniHelper.getSqrtPrice(_underlyingAssetStatus.sqrtAssetStatus.uniswapPool);

            uint256 liquidationSlippageSqrtTolerance = calculateLiquidationSlippageTolerance(debtValue);
            penaltyAmount = calculatePenaltyAmount(debtValue);

            require(
                sqrtTwap * 1e6 / (1e6 + liquidationSlippageSqrtTolerance) <= sqrtPrice
                    && sqrtPrice <= sqrtTwap * (1e6 + liquidationSlippageSqrtTolerance) / 1e6,
                "L3"
            );
        }

        emit PositionLiquidated(
            _vaultId, _underlyingAssetStatus.id, tradeAmount, tradeAmountSqrt, tradeResult.payoff, tradeResult.fee
        );
    }

    function calculateLiquidationSlippageTolerance(uint256 _debtValue) internal pure returns (uint256) {
        uint256 liquidationSlippageSqrtTolerance = Math.max(
            Constants.LIQ_SLIPPAGE_SQRT_SLOPE * (FixedPointMathLib.sqrt(_debtValue * 1e6)) / 1e6
                + Constants.LIQ_SLIPPAGE_SQRT_BASE,
            Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE
        );

        if (liquidationSlippageSqrtTolerance > 1e6) {
            return 1e6;
        }

        return liquidationSlippageSqrtTolerance;
    }

    function calculatePenaltyAmount(uint256 _debtValue) internal pure returns (uint256) {
        // penalty amount is 0.05% of debt value
        return Math.max(
            ((_debtValue / 2000) / Constants.MARGIN_ROUNDED_DECIMALS) * Constants.MARGIN_ROUNDED_DECIMALS,
            Constants.MIN_PENALTY
        );
    }
}

