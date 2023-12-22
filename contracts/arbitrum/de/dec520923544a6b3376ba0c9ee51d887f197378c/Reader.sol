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
    function getDelta(uint256 _pairId, uint256 _vaultId) external view returns (int256 _delta) {
        DataType.PairStatus memory asset = controller.getAsset(_pairId);

        return ReaderLogic.getDelta(asset.id, controller.getVault(_vaultId), controller.getSqrtPrice(_pairId));
    }

    /**
     * @notice Gets asset utilization ratios
     * @param _pairId The id of asset pair
     * @return sqrtAsset The utilization of sqrt asset
     * @return stableAsset The utilization of stable asset
     * @return underlyingAsset The utilization of underlying asset
     */
    function getUtilizationRatio(uint256 _pairId)
        external
        view
        returns (uint256 sqrtAsset, uint256 stableAsset, uint256 underlyingAsset)
    {
        DataType.PairStatus memory pair = controller.getAsset(_pairId);

        return ReaderLogic.getUtilizationRatio(pair);
    }
}

