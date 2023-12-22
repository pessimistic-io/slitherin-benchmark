// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { LOVCalculations } from "./LOVCalculations.sol";
import { ILOVProduct } from "./ILOVProduct.sol";
import { IFCNVault } from "./IFCNVault.sol";
import { Deposit, FCNVaultMetadata, FCNVaultAssetInfo } from "./Structs.sol";

contract LOVProductViewer {
    struct LOVProductInfo {
        address asset;
        string name;
        uint256 managementFeeBps; // basis points
        uint256 yieldFeeBps; // basis points
    }

    function getLOVProductInfo(address lovProductAddress) external view returns (LOVProductInfo memory) {
        ILOVProduct lovProduct = ILOVProduct(lovProductAddress);
        return
            LOVProductInfo({
                asset: lovProduct.asset(),
                name: lovProduct.name(),
                managementFeeBps: lovProduct.managementFeeBps(),
                yieldFeeBps: lovProduct.yieldFeeBps()
            });
    }

    function getLOVProductUserQueuedDeposits(
        address fcnProductAddress,
        address userAddress,
        uint256 leverage
    ) external view returns (uint256 totalQueuedDeposits) {
        ILOVProduct lovProduct = ILOVProduct(fcnProductAddress);
        uint256 queuedDepositsCount = lovProduct.getDepositQueueCount(leverage);

        totalQueuedDeposits = 0;
        for (uint256 i = 0; i < queuedDepositsCount; i++) {
            Deposit memory d = lovProduct.depositQueues(leverage, i);

            if (d.receiver == userAddress) {
                totalQueuedDeposits += d.amount;
            }
        }

        return totalQueuedDeposits;
    }

    function getLOVProductQueuedDeposits(
        address fcnProductAddress,
        uint256 leverage
    ) external view returns (uint256 totalQueuedDeposits) {
        ILOVProduct lovProduct = ILOVProduct(fcnProductAddress);
        uint256 queuedDepositsCount = lovProduct.getDepositQueueCount(leverage);

        totalQueuedDeposits = 0;
        for (uint256 i = 0; i < queuedDepositsCount; i++) {
            Deposit memory d = lovProduct.depositQueues(leverage, i);

            totalQueuedDeposits += d.amount;
        }

        return totalQueuedDeposits;
    }

    function getLOVVaultMetadata(
        address productAddress,
        uint256 leverage
    ) external view returns (FCNVaultMetadata[] memory) {
        ILOVProduct lovProduct = ILOVProduct(productAddress);

        address[] memory vaultAddresses = lovProduct.getVaultAddresses(leverage);

        FCNVaultMetadata[] memory vaultMetadata = new FCNVaultMetadata[](vaultAddresses.length);

        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            vaultMetadata[i] = lovProduct.getVaultMetadata(vaultAddresses[i]);
        }

        return vaultMetadata;
    }

    function getLOVVaultAssetInfo(
        address productAddress,
        uint256 leverage,
        uint256 inputAssets,
        uint256 inputShares
    ) external view returns (FCNVaultAssetInfo[] memory) {
        ILOVProduct lovProduct = ILOVProduct(productAddress);

        address[] memory vaultAddresses = lovProduct.getVaultAddresses(leverage);

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

    /**
     * @notice Calculates the fees that should be collected from a given vault
     * Putting logic in viewer to save space in LOVProduct contract.
     * @param productAddress is the address of the LOVProduct
     * @param vaultAddress is the address of the vault
     * @param managementFeeBps is the management fee in bps
     * @param yieldFeeBps is the yield fee in bps
     */
    function calculateFees(
        address productAddress,
        address vaultAddress,
        uint256 managementFeeBps,
        uint256 yieldFeeBps
    ) public view returns (uint256 totalFee, uint256 managementFee, uint256 yieldFee) {
        ILOVProduct lovProduct = ILOVProduct(productAddress);
        FCNVaultMetadata memory vaultMetadata = lovProduct.getVaultMetadata(vaultAddress);

        return
            LOVCalculations.calculateFees(
                vaultMetadata.underlyingAmount,
                vaultMetadata.vaultStart,
                vaultMetadata.tradeExpiry,
                vaultMetadata.vaultFinalPayoff,
                managementFeeBps,
                yieldFeeBps
            );
    }

    /**
     * @notice Calculates the percentage of principal to return to users if a knock in occurs.
     * Iterates through all knock-in barriers and checks the ratio of (spot/strike) for each asset
     * Returns the minimum of the knock-in ratios.
     * Putting logic in viewer to save space in LOVProduct contract.
     * @param productAddress is address of LOVProduct
     * @param vaultAddress is address of the vault
     * @param cegaStateAddress is address of CegaState
     */
    function calculateKnockInRatio(
        address productAddress,
        address vaultAddress,
        address cegaStateAddress
    ) public view returns (uint256 knockInRatio) {
        ILOVProduct lovProduct = ILOVProduct(productAddress);
        FCNVaultMetadata memory vaultMetadata = lovProduct.getVaultMetadata(vaultAddress);

        return
            LOVCalculations.calculateKnockInRatio(
                vaultMetadata.optionBarriers,
                vaultMetadata.optionBarriersCount,
                cegaStateAddress
            );
    }
}

