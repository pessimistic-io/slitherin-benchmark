// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "./TransferHelper.sol";
import "./FixedPointMathLib.sol";
import "./DataType.sol";
import "./Perp.sol";
import "./PositionCalculator.sol";
import "./ScaledAsset.sol";
import "./VaultLib.sol";
import "./TradeLogic.sol";
import "./ApplyInterestLib.sol";

/*
 * Error Codes
 * L1: vault must be danger before liquidation
 * L2: vault must be (safe if there are positions) or (margin is negative if there are no positions) after liquidation
 * L3: too much slippage
 * L4: close ratio must be between 0 and 1e18
 */
library LiquidationLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;
    using VaultLib for DataType.Vault;

    event PositionLiquidated(
        uint256 vaultId, uint256 pairId, int256 tradeAmount, int256 tradeSqrtAmount, Perp.Payoff payoff, int256 fee
    );
    event VaultLiquidated(
        uint256 vaultId,
        uint256 mainVaultId,
        uint256 withdrawnMarginAmount,
        address liquidator,
        int256 totalPenaltyAmount
    );

    function execLiquidationCall(
        DataType.GlobalData storage _globalData,
        uint256 _vaultId,
        uint256 _closeRatio,
        uint256 _sqrtSlippageTolerance
    ) external {
        DataType.Vault storage vault = _globalData.vaults[_vaultId];
        DataType.PairGroup memory pairGroup = _globalData.pairGroups[vault.pairGroupId];

        // Checks vaultId exists
        VaultLib.validateVaultId(_globalData, _vaultId);

        // Updates interest rate related to the vault
        ApplyInterestLib.applyInterestForVault(vault, _globalData.pairs);

        uint256 mainVaultId = _globalData.ownVaultsMap[vault.owner][pairGroup.id].mainVaultId;

        (int256 penaltyAmount) = _execLiquidationCall(
            pairGroup, _globalData, vault, _globalData.vaults[mainVaultId], _closeRatio, _sqrtSlippageTolerance
        );

        if (penaltyAmount > 0) {
            TransferHelper.safeTransfer(pairGroup.stableTokenAddress, msg.sender, uint256(penaltyAmount));
        } else if (penaltyAmount < 0) {
            TransferHelper.safeTransferFrom(
                pairGroup.stableTokenAddress, msg.sender, address(this), uint256(-penaltyAmount)
            );
        }
    }

    function _execLiquidationCall(
        DataType.PairGroup memory _pairGroup,
        DataType.GlobalData storage _globalData,
        DataType.Vault storage _vault,
        DataType.Vault storage _mainVault,
        uint256 _closeRatio,
        uint256 _liquidationSlippageSqrtTolerance
    ) internal returns (int256 totalPenaltyAmount) {
        require(1e17 <= _closeRatio && _closeRatio <= Constants.ONE, "L4");

        // The vault must be danger
        require(PositionCalculator.isLiquidatable(_globalData.pairs, _globalData.rebalanceFeeGrowthCache, _vault), "ND");

        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            Perp.UserStatus storage userStatus = _vault.openPositions[i];

            (int256 totalPayoff, uint256 penaltyAmount) = closePerp(
                _vault.id,
                _pairGroup,
                _globalData.pairs[userStatus.pairId],
                _globalData.rebalanceFeeGrowthCache,
                userStatus,
                _closeRatio,
                _liquidationSlippageSqrtTolerance
            );

            _vault.margin += totalPayoff;
            totalPenaltyAmount += int256(penaltyAmount);
        }

        _vault.cleanOpenPosition();

        (_vault.margin, totalPenaltyAmount) = calculatePayableReward(_vault.margin, uint256(totalPenaltyAmount));

        // The vault must be safe after liquidation call
        bool hasPosition = PositionCalculator.getHasPosition(_vault);

        int256 withdrawnMarginAmount;

        // If the vault is isolated and margin is not negative, the contract moves vault's margin to the main vault.
        if (
            !_vault.autoTransferDisabled && !hasPosition && _mainVault.id > 0 && _vault.id != _mainVault.id
                && _vault.margin > 0
        ) {
            withdrawnMarginAmount = _vault.margin;

            _mainVault.margin += _vault.margin;

            _vault.margin = 0;
        }

        // withdrawnMarginAmount is always positive because it's checked in before lines
        emit VaultLiquidated(_vault.id, _mainVault.id, uint256(withdrawnMarginAmount), msg.sender, totalPenaltyAmount);
    }

    /**
     * @notice Calculated liquidation reward
     * @param reserveBefore margin amount before calculating liquidation reward
     * @param expectedReward calculated liquidation reward
     * @return reserveAfter margin amount after calculation
     * @return payableReward if payableReward is positive then it stands for liquidation reward.
     *  if negative payableReward stands for insufficient margin amount.
     */
    function calculatePayableReward(int256 reserveBefore, uint256 expectedReward)
        internal
        pure
        returns (int256 reserveAfter, int256 payableReward)
    {
        if (reserveBefore >= int256(expectedReward)) {
            return (reserveBefore - int256(expectedReward), int256(expectedReward));
        } else if (reserveBefore >= 0) {
            return (0, reserveBefore);
        } else {
            return (0, reserveBefore);
        }
    }

    function closePerp(
        uint256 _vaultId,
        DataType.PairGroup memory _pairGroup,
        DataType.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _perpUserStatus,
        uint256 _closeRatio,
        uint256 _sqrtSlippageTolerance
    ) internal returns (int256 totalPayoff, uint256 penaltyAmount) {
        int256 tradeAmount = -_perpUserStatus.perp.amount * int256(_closeRatio) / int256(Constants.ONE);
        int256 tradeAmountSqrt = -_perpUserStatus.sqrtPerp.amount * int256(_closeRatio) / int256(Constants.ONE);

        uint160 sqrtTwap = UniHelper.getSqrtTWAP(_pairStatus.sqrtAssetStatus.uniswapPool);

        DataType.TradeResult memory tradeResult = TradeLogic.trade(
            _pairGroup, _pairStatus, _rebalanceFeeGrowthCache, _perpUserStatus, tradeAmount, tradeAmountSqrt
        );

        totalPayoff = tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        {
            // reverts if price is out of slippage threshold
            uint256 sqrtPrice = UniHelper.getSqrtPrice(_pairStatus.sqrtAssetStatus.uniswapPool);

            uint256 liquidationSlippageSqrtTolerance = calculateLiquidationSlippageTolerance(_sqrtSlippageTolerance);
            penaltyAmount = calculatePenaltyAmount(_pairGroup.marginRoundedDecimal);
            penaltyAmount = uint256(
                Trade.roundMargin(
                    int256(penaltyAmount * _closeRatio / Constants.ONE), 10 ** _pairGroup.marginRoundedDecimal
                )
            );

            require(
                sqrtTwap * 1e6 / (1e6 + liquidationSlippageSqrtTolerance) <= sqrtPrice
                    && sqrtPrice <= sqrtTwap * (1e6 + liquidationSlippageSqrtTolerance) / 1e6,
                "L3"
            );
        }

        emit PositionLiquidated(
            _vaultId, _pairStatus.id, tradeAmount, tradeAmountSqrt, tradeResult.payoff, tradeResult.fee
        );
    }

    function calculateLiquidationSlippageTolerance(uint256 _sqrtSlippageTolerance) internal pure returns (uint256) {
        if (_sqrtSlippageTolerance == 0) {
            return Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE;
        } else if (_sqrtSlippageTolerance <= Constants.MAX_LIQ_SLIPPAGE_SQRT_TOLERANCE) {
            return _sqrtSlippageTolerance;
        } else {
            return Constants.MAX_LIQ_SLIPPAGE_SQRT_TOLERANCE;
        }
    }

    function calculatePenaltyAmount(uint8 _marginRoundedDecimal) internal pure returns (uint256) {
        return 100 * (10 ** _marginRoundedDecimal);
    }
}

