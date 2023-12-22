// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "./TransferHelper.sol";
import "./AssetGroupLib.sol";
import "./Perp.sol";
import "./ScaledAsset.sol";
import "./AssetLib.sol";

library ApplyInterestLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event InterestGrowthUpdated(
        uint256 assetId,
        uint256 assetGrowth,
        uint256 debtGrowth,
        uint256 supplyPremiumGrowth,
        uint256 borrowPremiumGrowth,
        uint256 fee0Growth,
        uint256 fee1Growth,
        uint256 accumulatedProtocolRevenue
    );

    function applyInterestForAssetGroup(
        DataType.AssetGroup storage _assetGroup,
        mapping(uint256 => DataType.AssetStatus) storage _assets
    ) external {
        applyInterestForToken(_assets, Constants.STABLE_ASSET_ID);

        for (uint256 i = 0; i < _assetGroup.assetIds.length; i++) {
            applyInterestForToken(_assets, _assetGroup.assetIds[i]);
        }
    }

    function applyInterestForToken(mapping(uint256 => DataType.AssetStatus) storage _assets, uint256 _assetId) public {
        DataType.AssetStatus storage assetStatus = _assets[_assetId];

        require(assetStatus.id > 0, "A0");

        if (block.timestamp <= assetStatus.lastUpdateTimestamp) {
            return;
        }

        if (_assetId != Constants.STABLE_ASSET_ID) {
            _assets[Constants.STABLE_ASSET_ID].accumulatedProtocolRevenue += Perp.updateFeeAndPremiumGrowth(
                assetStatus.sqrtAssetStatus,
                assetStatus.squartIRMParams,
                assetStatus.isMarginZero,
                assetStatus.lastUpdateTimestamp
            );
        }

        // Gets utilization ratio
        uint256 utilizationRatio = assetStatus.tokenStatus.getUtilizationRatio();

        if (utilizationRatio == 0) {
            // Update last update timestamp
            assetStatus.lastUpdateTimestamp = block.timestamp;

            emitInterestGrowthEvent(assetStatus);

            return;
        }

        // Calculates interest rate
        uint256 interestRate = InterestRateModel.calculateInterestRate(assetStatus.irmParams, utilizationRatio)
            * (block.timestamp - assetStatus.lastUpdateTimestamp) / 365 days;

        // Update scaler
        assetStatus.accumulatedProtocolRevenue += assetStatus.tokenStatus.updateScaler(interestRate);

        // Update last update timestamp
        assetStatus.lastUpdateTimestamp = block.timestamp;

        emitInterestGrowthEvent(assetStatus);
    }

    function emitInterestGrowthEvent(DataType.AssetStatus memory _assetStatus) internal {
        emit InterestGrowthUpdated(
            _assetStatus.id,
            _assetStatus.tokenStatus.assetGrowth,
            _assetStatus.tokenStatus.debtGrowth,
            _assetStatus.sqrtAssetStatus.supplyPremiumGrowth,
            _assetStatus.sqrtAssetStatus.borrowPremiumGrowth,
            _assetStatus.sqrtAssetStatus.fee0Growth,
            _assetStatus.sqrtAssetStatus.fee1Growth,
            _assetStatus.accumulatedProtocolRevenue
        );
    }

    function reallocate(mapping(uint256 => DataType.AssetStatus) storage _assets, uint256 _assetId)
        external
        returns (bool reallocationHappened, int256 profit)
    {
        DataType.AssetStatus storage underlyingAsset = _assets[_assetId];
        DataType.AssetStatus storage stableAsset = _assets[Constants.STABLE_ASSET_ID];

        AssetLib.checkUnderlyingAsset(_assetId, underlyingAsset);

        (reallocationHappened, profit) =
            Perp.reallocate(underlyingAsset, stableAsset.tokenStatus, underlyingAsset.sqrtAssetStatus, false);

        if (profit < 0) {
            address token;

            if (underlyingAsset.isMarginZero) {
                token = underlyingAsset.token;
            } else {
                token = stableAsset.token;
            }

            TransferHelper.safeTransferFrom(token, msg.sender, address(this), uint256(-profit));
        }
    }
}

