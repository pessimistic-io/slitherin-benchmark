// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./PairLib.sol";
import "./Perp.sol";
import "./SafeCast.sol";

library PerpFee {
    using ScaledAsset for ScaledAsset.TokenStatus;
    using SafeCast for uint256;

    function computeUserFee(
        DataType.PairStatus memory _assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus memory _userStatus
    ) internal view returns (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) {
        unrealizedFeeUnderlying = _assetStatus.underlyingPool.tokenStatus.computeUserFee(_userStatus.underlying);
        unrealizedFeeStable = _assetStatus.stablePool.tokenStatus.computeUserFee(_userStatus.stable);

        {
            (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) = computeRebalanceEntryFee(
                _assetStatus.id, _assetStatus.sqrtAssetStatus, _rebalanceFeeGrowthCache, _userStatus
            );
            unrealizedFeeUnderlying += rebalanceFeeUnderlying;
            unrealizedFeeStable += rebalanceFeeStable;
        }

        {
            (int256 feeUnderlying, int256 feeStable) = computePremium(_assetStatus, _userStatus.sqrtPerp);
            unrealizedFeeUnderlying += feeUnderlying;
            unrealizedFeeStable += feeStable;
        }
    }

    function settleUserFee(
        DataType.PairStatus storage _assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 totalFeeUnderlying, int256 totalFeeStable) {
        // settle asset interest
        totalFeeUnderlying = _assetStatus.underlyingPool.tokenStatus.settleUserFee(_userStatus.underlying);
        totalFeeStable = _assetStatus.stablePool.tokenStatus.settleUserFee(_userStatus.stable);

        // settle rebalance interest
        (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) = settleRebalanceEntryFee(
            _assetStatus.id, _assetStatus.sqrtAssetStatus, _rebalanceFeeGrowthCache, _userStatus
        );

        // settle trade fee
        (int256 feeUnderlying, int256 feeStable) = settlePremium(_assetStatus, _userStatus.sqrtPerp);

        totalFeeStable += feeStable + rebalanceFeeStable;
        totalFeeUnderlying += feeUnderlying + rebalanceFeeUnderlying;
    }

    // Trade fee and premium

    function computePremium(DataType.PairStatus memory _underlyingAssetStatus, Perp.SqrtPositionStatus memory _sqrtPerp)
        internal
        pure
        returns (int256 feeUnderlying, int256 feeStable)
    {
        uint256 growthDiff0;
        uint256 growthDiff1;

        if (_sqrtPerp.amount > 0) {
            growthDiff0 = _underlyingAssetStatus.sqrtAssetStatus.fee0Growth - _sqrtPerp.entryTradeFee0;
            growthDiff1 = _underlyingAssetStatus.sqrtAssetStatus.fee1Growth - _sqrtPerp.entryTradeFee1;
        } else if (_sqrtPerp.amount < 0) {
            growthDiff0 = _underlyingAssetStatus.sqrtAssetStatus.borrowPremium0Growth - _sqrtPerp.entryTradeFee0;
            growthDiff1 = _underlyingAssetStatus.sqrtAssetStatus.borrowPremium1Growth - _sqrtPerp.entryTradeFee1;
        } else {
            return (feeUnderlying, feeStable);
        }

        int256 fee0 = Math.mulDivDownInt256(_sqrtPerp.amount, growthDiff0, Constants.Q128);
        int256 fee1 = Math.mulDivDownInt256(_sqrtPerp.amount, growthDiff1, Constants.Q128);

        if (_underlyingAssetStatus.isMarginZero) {
            feeStable = fee0;
            feeUnderlying = fee1;
        } else {
            feeUnderlying = fee0;
            feeStable = fee1;
        }
    }

    function settlePremium(DataType.PairStatus memory _underlyingAssetStatus, Perp.SqrtPositionStatus storage _sqrtPerp)
        internal
        returns (int256 feeUnderlying, int256 feeStable)
    {
        (feeUnderlying, feeStable) = computePremium(_underlyingAssetStatus, _sqrtPerp);

        if (_sqrtPerp.amount > 0) {
            _sqrtPerp.entryTradeFee0 = _underlyingAssetStatus.sqrtAssetStatus.fee0Growth;
            _sqrtPerp.entryTradeFee1 = _underlyingAssetStatus.sqrtAssetStatus.fee1Growth;
        } else if (_sqrtPerp.amount < 0) {
            _sqrtPerp.entryTradeFee0 = _underlyingAssetStatus.sqrtAssetStatus.borrowPremium0Growth;
            _sqrtPerp.entryTradeFee1 = _underlyingAssetStatus.sqrtAssetStatus.borrowPremium1Growth;
        }
    }

    // Rebalance fee

    function computeRebalanceEntryFee(
        uint256 _assetId,
        Perp.SqrtPerpAssetStatus memory _assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus memory _userStatus
    ) internal view returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) {
        if (_userStatus.sqrtPerp.amount > 0 && _userStatus.lastNumRebalance < _assetStatus.numRebalance) {
            uint256 rebalanceId = PairLib.getRebalanceCacheId(_assetId, _userStatus.lastNumRebalance);

            rebalanceFeeUnderlying = Math.mulDivDownInt256(
                _assetStatus.rebalanceFeeGrowthUnderlying - _rebalanceFeeGrowthCache[rebalanceId].underlyingGrowth,
                uint256(_userStatus.sqrtPerp.amount),
                Constants.ONE
            );
            rebalanceFeeStable = Math.mulDivDownInt256(
                _assetStatus.rebalanceFeeGrowthStable - _rebalanceFeeGrowthCache[rebalanceId].stableGrowth,
                uint256(_userStatus.sqrtPerp.amount),
                Constants.ONE
            );
        }
    }

    function settleRebalanceEntryFee(
        uint256 _assetId,
        Perp.SqrtPerpAssetStatus storage _assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) {
        if (_userStatus.sqrtPerp.amount > 0 && _userStatus.lastNumRebalance < _assetStatus.numRebalance) {
            (rebalanceFeeUnderlying, rebalanceFeeStable) =
                computeRebalanceEntryFee(_assetId, _assetStatus, _rebalanceFeeGrowthCache, _userStatus);

            _assetStatus.lastRebalanceTotalSquartAmount -= uint256(_userStatus.sqrtPerp.amount);
        }

        _userStatus.lastNumRebalance = _assetStatus.numRebalance;
    }
}

