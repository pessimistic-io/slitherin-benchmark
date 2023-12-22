// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./DataType.sol";

library AssetLib {
    function checkUnderlyingAsset(uint256 _assetId, DataType.AssetStatus memory underlyingAsset) internal pure {
        require(_assetId != Constants.STABLE_ASSET_ID && underlyingAsset.id > 0, "ASSETID");
    }
}

