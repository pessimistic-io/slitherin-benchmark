// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IFCNProduct } from "./IFCNProduct.sol";
import { IFCNVault } from "./IFCNVault.sol";
import { Deposit, FCNVaultMetadata, FCNVaultAssetInfo } from "./Structs.sol";

contract FCNProductViewer {
    struct FCNProductInfo {
        address asset;
        string name;
        uint256 managementFeeBps; // basis points
        uint256 yieldFeeBps; // basis points
        bool isDepositQueueOpen;
        uint256 maxDepositAmountLimit;
        uint256 sumVaultUnderlyingAmounts;
        uint256 queuedDepositsTotalAmount;
        uint256 queuedDepositsCount;
        address[] vaultAddresses;
    }

    function getFCNProductInfo(address fcnProductAddress) external view returns (FCNProductInfo memory) {
        IFCNProduct fcnProduct = IFCNProduct(fcnProductAddress);
        return
            FCNProductInfo({
                asset: fcnProduct.asset(),
                name: fcnProduct.name(),
                managementFeeBps: fcnProduct.managementFeeBps(),
                yieldFeeBps: fcnProduct.yieldFeeBps(),
                isDepositQueueOpen: fcnProduct.isDepositQueueOpen(),
                maxDepositAmountLimit: fcnProduct.maxDepositAmountLimit(),
                sumVaultUnderlyingAmounts: fcnProduct.sumVaultUnderlyingAmounts(),
                queuedDepositsTotalAmount: fcnProduct.queuedDepositsTotalAmount(),
                queuedDepositsCount: fcnProduct.queuedDepositsCount(),
                vaultAddresses: fcnProduct.getVaultAddresses()
            });
    }

    function getFCNProductUserQueuedDeposits(
        address fcnProductAddress,
        address userAddress
    ) external view returns (uint256 totalQueuedDeposits) {
        IFCNProduct fcnProduct = IFCNProduct(fcnProductAddress);
        uint256 queuedDepositsCount = fcnProduct.queuedDepositsCount();

        totalQueuedDeposits = 0;
        for (uint256 i = 0; i < queuedDepositsCount; i++) {
            Deposit memory d = fcnProduct.depositQueue(i);

            if (d.receiver == userAddress) {
                totalQueuedDeposits += d.amount;
            }
        }

        return totalQueuedDeposits;
    }

    function getFCNVaultMetadata(address productAddress) external view returns (FCNVaultMetadata[] memory) {
        IFCNProduct fcnProduct = IFCNProduct(productAddress);

        address[] memory vaultAddresses = fcnProduct.getVaultAddresses();

        FCNVaultMetadata[] memory vaultMetadata = new FCNVaultMetadata[](vaultAddresses.length);

        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            vaultMetadata[i] = fcnProduct.getVaultMetadata(vaultAddresses[i]);
        }

        return vaultMetadata;
    }

    function getFCNVaultAssetInfo(
        address productAddress,
        uint256 inputAssets,
        uint256 inputShares
    ) external view returns (FCNVaultAssetInfo[] memory) {
        IFCNProduct fcnProduct = IFCNProduct(productAddress);

        address[] memory vaultAddresses = fcnProduct.getVaultAddresses();

        FCNVaultAssetInfo[] memory assetInfo = new FCNVaultAssetInfo[](vaultAddresses.length);

        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            IFCNVault vault = IFCNVault(vaultAddresses[i]);

            assetInfo[i] = FCNVaultAssetInfo({
                vaultAddress: address(vault),
                totalAssets: vault.totalAssets(),
                totalSupply: vault.totalSupply(),
                inputAssets: inputAssets,
                outputShares: vault.convertToShares(inputAssets),
                inputShares: inputShares,
                outputAssets: vault.convertToAssets(inputShares)
            });
        }

        return assetInfo;
    }
}

