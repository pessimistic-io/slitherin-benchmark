// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./DataType.sol";

library AssetGroupLib {
    function setStableAssetId(DataType.AssetGroup storage _assetGroup, uint256 _stableAssetId) internal {
        _assetGroup.stableAssetId = _stableAssetId;
        appendTokenId(_assetGroup, _stableAssetId);
    }

    function appendTokenId(DataType.AssetGroup storage _assetGroup, uint256 _assetId) internal {
        _assetGroup.assetIds.push(_assetId);
    }

    function isAllow(DataType.AssetGroup memory _assetGroup, uint256 _assetId) internal pure returns (bool) {
        for (uint256 i = 0; i < _assetGroup.assetIds.length; i++) {
            if (_assetGroup.assetIds[i] == _assetId) {
                return true;
            }
        }

        return false;
    }
}

