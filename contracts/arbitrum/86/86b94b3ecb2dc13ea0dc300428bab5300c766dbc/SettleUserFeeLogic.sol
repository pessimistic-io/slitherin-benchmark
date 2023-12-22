// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./AssetGroupLib.sol";
import "./Trade.sol";
import "./ScaledAsset.sol";
import "./UniHelper.sol";

library SettleUserFeeLogic {
    event FeeCollected(uint256 vaultId, uint256 assetId, int256 feeCollected);

    function settleUserFee(mapping(uint256 => DataType.AssetStatus) storage _assets, DataType.Vault storage _vault)
        external
        returns (int256[] memory latestFees, bool isSettled)
    {
        return settleUserFee(_assets, _vault, 0);
    }

    function settleUserFee(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        uint256 _excludeAssetId
    ) public returns (int256[] memory latestFees, bool isSettledTotal) {
        latestFees = new int256[](_vault.openPositions.length);

        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            uint256 assetId = _vault.openPositions[i].assetId;

            if (assetId == Constants.STABLE_ASSET_ID || assetId == _excludeAssetId) {
                continue;
            }

            (int256 fee, bool isSettled) =
                Trade.settleFee(_assets[assetId], _assets[Constants.STABLE_ASSET_ID], _vault.openPositions[i].perpTrade);

            isSettledTotal = isSettledTotal || isSettled;

            latestFees[i] = fee;

            _vault.margin += fee;

            emit FeeCollected(_vault.id, assetId, fee);

            UniHelper.checkPriceByTWAP(_assets[assetId].sqrtAssetStatus.uniswapPool);
        }
    }
}

