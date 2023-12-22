// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IProduct } from "./IProduct.sol";
import { IFCNVault } from "./IFCNVault.sol";
import { FCNVaultMetadata, FCNVaultAssetInfo } from "./Structs.sol";

contract FCNVaultViewer {
    function getSingleFCNVaultMetadata(
        address productAddress,
        address fcnVaultAddress
    ) external view returns (FCNVaultMetadata memory) {
        IProduct product = IProduct(productAddress);

        return product.getVaultMetadata(fcnVaultAddress);
    }

    function getSingleFCNVaultAssetInfo(
        address fcnVaultAddress,
        uint256 inputAssets,
        uint256 inputShares
    ) external view returns (FCNVaultAssetInfo memory) {
        IFCNVault vault = IFCNVault(fcnVaultAddress);

        return
            FCNVaultAssetInfo({
                vaultAddress: fcnVaultAddress,
                totalAssets: vault.totalAssets(),
                totalSupply: vault.totalSupply(),
                inputAssets: inputAssets,
                outputShares: vault.convertToShares(inputAssets),
                inputShares: inputShares,
                outputAssets: vault.convertToAssets(inputShares)
            });
    }
}

