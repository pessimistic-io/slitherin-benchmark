// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.15;

import "./IController.sol";
import "./DataType.sol";
import "./ReaderLogic.sol";

/**
 * @title Reader contract
 * @notice Reader contract with an controller
 */
contract Reader {
    IController public controller;

    /**
     * @notice Reader constructor
     * @param _controller controller address
     */
    constructor(IController _controller) {
        controller = _controller;
    }

    /**
     * @notice Gets vault delta.
     */
    function getDelta(uint256 _assetId, uint256 _vaultId) external view returns (int256 _delta) {
        DataType.AssetStatus memory asset = controller.getAsset(_assetId);

        return ReaderLogic.getDelta(asset.id, controller.getVault(_vaultId), controller.getSqrtPrice(_assetId));
    }
}

