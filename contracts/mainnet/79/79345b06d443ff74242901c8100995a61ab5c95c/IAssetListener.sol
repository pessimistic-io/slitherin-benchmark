// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./PositionSnapshot.sol";
import "./AssetTransferData.sol";
import "./ItemRef.sol";

interface IAssetListener {
    function beforeAssetTransfer(AssetTransferData calldata arg) external;

    function afterAssetTransfer(AssetTransferData calldata arg)
        external
        payable;
}

