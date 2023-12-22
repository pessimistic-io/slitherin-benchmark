// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./DataType.sol";
import "./TradeLogic.sol";

interface IController {
    function tradePerp(uint256 _vaultId, uint256 _assetId, TradeLogic.TradeParams memory _tradeParams)
        external
        returns (DataType.TradeResult memory);

    function updateMargin(int256 _marginAmount) external returns (uint256 vaultId);

    function getSqrtPrice(uint256 _assetId) external view returns (uint160);

    function getVault(uint256 _id) external view returns (DataType.Vault memory);

    function getAssetGroup() external view returns (DataType.AssetGroup memory);

    function getAsset(uint256 _assetId) external view returns (DataType.AssetStatus memory);

    function getVaultStatus(uint256 _id) external returns (DataType.VaultStatusResult memory);
}

