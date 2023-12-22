// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./DataType.sol";
import "./Perp.sol";
import "./PositionCalculator.sol";
import "./ScaledAsset.sol";
import "./ApplyInterestLib.sol";

library ReaderLogic {
    using Perp for Perp.SqrtPerpAssetStatus;
    using ScaledAsset for ScaledAsset.TokenStatus;

    function getLatestAssetStatus(DataType.GlobalData storage _globalData, uint256 _id)
        external
        returns (DataType.PairStatus memory)
    {
        ApplyInterestLib.applyInterestForToken(_globalData.pairs, _id);

        return _globalData.pairs[_id];
    }

    function getVaultStatus(
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault memory _vault
    ) external returns (DataType.VaultStatusResult memory) {
        ApplyInterestLib.applyInterestForVault(_vault, _pairs);

        DataType.SubVaultStatusResult[] memory subVaults =
            new DataType.SubVaultStatusResult[](_vault.openPositions.length);

        for (uint256 i; i < _vault.openPositions.length; i++) {
            Perp.UserStatus memory userStatus = _vault.openPositions[i];

            bool isMarginZero = _pairs[userStatus.pairId].isMarginZero;
            uint160 sqrtPrice = UniHelper.convertSqrtPrice(
                UniHelper.getSqrtTWAP(_pairs[userStatus.pairId].sqrtAssetStatus.uniswapPool), isMarginZero
            );

            subVaults[i].pairId = userStatus.pairId;
            subVaults[i].position = userStatus;

            {
                subVaults[i].delta = calculateDelta(sqrtPrice, userStatus.sqrtPerp.amount, userStatus.perp.amount);
            }

            (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) =
                PerpFee.computeUserFee(_pairs[userStatus.pairId], _rebalanceFeeGrowthCache, userStatus);

            subVaults[i].unrealizedFee = PositionCalculator.calculateValue(
                sqrtPrice, PositionCalculator.PositionParams(unrealizedFeeStable, 0, unrealizedFeeUnderlying)
            );
        }

        (int256 minDeposit, int256 vaultValue,) =
            PositionCalculator.calculateMinDeposit(_pairs, _rebalanceFeeGrowthCache, _vault);

        return DataType.VaultStatusResult(
            _vault.id, vaultValue, _vault.margin, vaultValue - _vault.margin, minDeposit, subVaults
        );
    }

    /**
     * @notice Gets utilization ratio
     */
    function getUtilizationRatio(DataType.PairStatus memory _assetStatus)
        external
        pure
        returns (uint256, uint256, uint256)
    {
        return (
            _assetStatus.sqrtAssetStatus.getUtilizationRatio(),
            _assetStatus.stablePool.tokenStatus.getUtilizationRatio(),
            _assetStatus.underlyingPool.tokenStatus.getUtilizationRatio()
        );
    }

    function getDelta(uint256 _pairId, DataType.Vault memory _vault, uint160 _sqrtPrice)
        internal
        pure
        returns (int256 _delta)
    {
        for (uint256 i; i < _vault.openPositions.length; i++) {
            if (_pairId != _vault.openPositions[i].pairId) {
                continue;
            }

            _delta +=
                calculateDelta(_sqrtPrice, _vault.openPositions[i].sqrtPerp.amount, _vault.openPositions[i].perp.amount);
        }
    }

    function calculateDelta(uint256 _sqrtPrice, int256 _sqrtAmount, int256 perpAmount) internal pure returns (int256) {
        return perpAmount + _sqrtAmount * int256(Constants.Q96) / int256(_sqrtPrice);
    }
}

