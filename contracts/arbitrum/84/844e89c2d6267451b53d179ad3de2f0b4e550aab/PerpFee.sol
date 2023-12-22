// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./Perp.sol";

library PerpFee {
    using ScaledAsset for ScaledAsset.TokenStatus;

    function computeUserFee(
        DataType.AssetStatus memory _underlyingAssetStatus,
        ScaledAsset.TokenStatus memory _stableAssetStatus,
        Perp.UserStatus memory _userStatus
    ) internal pure returns (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) {
        unrealizedFeeUnderlying = _underlyingAssetStatus.tokenStatus.computeUserFee(_userStatus.underlying);
        unrealizedFeeStable = _stableAssetStatus.computeUserFee(_userStatus.stable);

        {
            (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) =
                computeRebalanceEntryFee(_underlyingAssetStatus.sqrtAssetStatus, _userStatus);
            unrealizedFeeUnderlying += rebalanceFeeUnderlying;
            unrealizedFeeStable += rebalanceFeeStable;
        }

        // settle premium
        {
            int256 premium = computePremium(_underlyingAssetStatus, _userStatus.sqrtPerp);
            unrealizedFeeStable += premium;
        }

        {
            (int256 feeUnderlying, int256 feeStable) = computeTradeFee(_underlyingAssetStatus, _userStatus.sqrtPerp);
            unrealizedFeeUnderlying += feeUnderlying;
            unrealizedFeeStable += feeStable;
        }
    }

    function settleUserFee(
        DataType.AssetStatus memory _underlyingAssetStatus,
        ScaledAsset.TokenStatus memory _stableAssetStatus,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 totalFeeUnderlying, int256 totalFeeStable) {
        // settle asset interest
        totalFeeUnderlying = _underlyingAssetStatus.tokenStatus.settleUserFee(_userStatus.underlying);
        totalFeeStable = _stableAssetStatus.settleUserFee(_userStatus.stable);

        // settle rebalance interest
        (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) =
            settleRebalanceEntryFee(_underlyingAssetStatus.sqrtAssetStatus, _userStatus);

        // settle premium
        int256 premium = settlePremium(_underlyingAssetStatus, _userStatus.sqrtPerp);

        // settle trade fee
        (int256 feeUnderlying, int256 feeStable) = settleTradeFee(_underlyingAssetStatus, _userStatus.sqrtPerp);

        totalFeeStable += feeStable + premium + rebalanceFeeStable;
        totalFeeUnderlying += feeUnderlying + rebalanceFeeUnderlying;
    }

    // Trade fee

    function computeTradeFee(
        DataType.AssetStatus memory _underlyingAssetStatus,
        Perp.SqrtPositionStatus memory _sqrtPerp
    ) internal pure returns (int256 feeUnderlying, int256 feeStable) {
        int256 fee0;
        int256 fee1;

        if (_sqrtPerp.amount > 0) {
            fee0 = mulDivToInt256(
                _underlyingAssetStatus.sqrtAssetStatus.fee0Growth - _sqrtPerp.entryTradeFee0, _sqrtPerp.amount
            );
            fee1 = mulDivToInt256(
                _underlyingAssetStatus.sqrtAssetStatus.fee1Growth - _sqrtPerp.entryTradeFee1, _sqrtPerp.amount
            );
        }

        if (_underlyingAssetStatus.isMarginZero) {
            feeStable = fee0;
            feeUnderlying = fee1;
        } else {
            feeUnderlying = fee0;
            feeStable = fee1;
        }
    }

    function settleTradeFee(
        DataType.AssetStatus memory _underlyingAssetStatus,
        Perp.SqrtPositionStatus storage _sqrtPerp
    ) internal returns (int256 feeUnderlying, int256 feeStable) {
        (feeUnderlying, feeStable) = computeTradeFee(_underlyingAssetStatus, _sqrtPerp);

        _sqrtPerp.entryTradeFee0 = _underlyingAssetStatus.sqrtAssetStatus.fee0Growth;
        _sqrtPerp.entryTradeFee1 = _underlyingAssetStatus.sqrtAssetStatus.fee1Growth;
    }

    // Premium

    function computePremium(
        DataType.AssetStatus memory _underlyingAssetStatus,
        Perp.SqrtPositionStatus memory _sqrtPerp
    ) internal pure returns (int256 premium) {
        if (_sqrtPerp.amount > 0) {
            premium = mulDivToInt256(
                _underlyingAssetStatus.sqrtAssetStatus.supplyPremiumGrowth - _sqrtPerp.entryPremium, _sqrtPerp.amount
            );
        } else if (_sqrtPerp.amount < 0) {
            premium = mulDivToInt256(
                _underlyingAssetStatus.sqrtAssetStatus.borrowPremiumGrowth - _sqrtPerp.entryPremium, _sqrtPerp.amount
            );
        }
    }

    function settlePremium(
        DataType.AssetStatus memory _underlyingAssetStatus,
        Perp.SqrtPositionStatus storage _sqrtPerp
    ) internal returns (int256 premium) {
        premium = computePremium(_underlyingAssetStatus, _sqrtPerp);

        if (_sqrtPerp.amount > 0) {
            _sqrtPerp.entryPremium = _underlyingAssetStatus.sqrtAssetStatus.supplyPremiumGrowth;
        } else if (_sqrtPerp.amount < 0) {
            _sqrtPerp.entryPremium = _underlyingAssetStatus.sqrtAssetStatus.borrowPremiumGrowth;
        }
    }

    // Rebalance fee

    function computeRebalanceEntryFee(Perp.SqrtPerpAssetStatus memory _assetStatus, Perp.UserStatus memory _userStatus)
        internal
        pure
        returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable)
    {
        if (_userStatus.sqrtPerp.amount > 0) {
            rebalanceFeeUnderlying = (
                _assetStatus.rebalanceFeeGrowthUnderlying - _userStatus.rebalanceEntryFeeUnderlying
            ) * _userStatus.sqrtPerp.amount / int256(Constants.ONE);

            rebalanceFeeStable = (_assetStatus.rebalanceFeeGrowthStable - _userStatus.rebalanceEntryFeeStable)
                * _userStatus.sqrtPerp.amount / int256(Constants.ONE);
        }
    }

    function settleRebalanceEntryFee(Perp.SqrtPerpAssetStatus memory _assetStatus, Perp.UserStatus storage _userStatus)
        internal
        returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable)
    {
        (rebalanceFeeUnderlying, rebalanceFeeStable) = computeRebalanceEntryFee(_assetStatus, _userStatus);

        _userStatus.rebalanceEntryFeeUnderlying = _assetStatus.rebalanceFeeGrowthUnderlying;
        _userStatus.rebalanceEntryFeeStable = _assetStatus.rebalanceFeeGrowthStable;
    }

    function mulDivToInt256(uint256 x, int256 y) internal pure returns (int256) {
        return SafeCast.toInt256(x) * y / int256(Constants.ONE);
    }
}

