// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { Math } from "./Math.sol";
import {     IERC20Metadata } from "./IERC20Metadata.sol";
import "./IERC721AUpgradeable.sol";

import {     CegaGlobalStorage,     Vault,     VaultStatus,     DepositQueue,     WithdrawalQueue,     Withdrawer,     MMNFTMetadata } from "./Structs.sol";
import { ITradeWinnerNFT } from "./ITradeWinnerNFT.sol";
import {     DCSProduct,     DCSVault,     DCSOptionType,     SettlementStatus } from "./DCSStructs.sol";
import { Transfers } from "./Transfers.sol";
import { VaultLogic } from "./VaultLogic.sol";
import { ICegaVault } from "./ICegaVault.sol";
import { ITreasury } from "./ITreasury.sol";
import {     IOracleEntry } from "./IOracleEntry.sol";
import { IAddressManager } from "./IAddressManager.sol";
import {     IRedepositManager } from "./IRedepositManager.sol";
import { Transfers } from "./Transfers.sol";

library DCSLogic {
    using Transfers for address;

    // EVENTS

    event DepositProcessed(
        address vaultAddress,
        address receiver,
        uint128 amount
    );

    event WithdrawalProcessed(
        address vaultAddress,
        uint256 sharesAmount,
        address owner,
        uint32 nextProductId
    );

    // MODIFIERS

    modifier onlyValidVault(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) {
        require(cgs.vaults[vaultAddress].vaultStartDate != 0, "400:VA");
        _;
    }

    // VIEW FUNCTIONS

    function getDCSProductDepositAsset(
        DCSProduct storage dcsProduct
    ) internal view returns (address) {
        return
            dcsProduct.dcsOptionType == DCSOptionType.BuyLow
                ? dcsProduct.quoteAssetAddress
                : dcsProduct.baseAssetAddress;
    }

    function getDCSProductSwapAsset(
        DCSProduct storage dcsProduct
    ) internal view returns (address) {
        return
            dcsProduct.dcsOptionType == DCSOptionType.BuyLow
                ? dcsProduct.baseAssetAddress
                : dcsProduct.quoteAssetAddress;
    }

    function getVaultSettlementAsset(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal view returns (address) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        bool isDefaulted = dcsVault.settlementStatus ==
            SettlementStatus.Defaulted;
        if (isDefaulted) {
            return
                dcsProduct.dcsOptionType == DCSOptionType.BuyLow
                    ? dcsProduct.quoteAssetAddress
                    : dcsProduct.baseAssetAddress;
        }
        if (dcsProduct.dcsOptionType == DCSOptionType.BuyLow) {
            return
                dcsVault.isPayoffInDepositAsset
                    ? dcsProduct.quoteAssetAddress
                    : dcsProduct.baseAssetAddress;
        } else {
            return
                dcsVault.isPayoffInDepositAsset
                    ? dcsProduct.baseAssetAddress
                    : dcsProduct.quoteAssetAddress;
        }
    }

    function getSpotPriceAt(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        IAddressManager addressManager,
        uint64 priceTimestamp
    ) internal view returns (uint256) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];

        uint256 price = cgs.oraclePriceOverride[vaultAddress][priceTimestamp];

        if (price > 0) {
            return price;
        }

        IOracleEntry iOracleEntry = IOracleEntry(
            addressManager.getCegaOracle()
        );

        // We always use baseAsset, even if the deposit asset is quote asset, because we
        // need to express the units of quote asset in terms of base asset
        return
            iOracleEntry.getPrice(
                dcsProduct.baseAssetAddress,
                dcsProduct.quoteAssetAddress,
                priceTimestamp,
                vault.dataSource
            );
    }

    function convertDepositUnitsToSwap(
        uint256 amountToConvert,
        IAddressManager addressManager,
        uint256 conversionPrice,
        address depositAsset,
        address swapAsset,
        DCSOptionType dcsOptionType
    ) internal view returns (uint256) {
        IOracleEntry iOracleEntry = IOracleEntry(
            addressManager.getCegaOracle()
        );
        uint8 depositAssetDecimals = VaultLogic.getAssetDecimals(depositAsset);
        uint8 swapAssetDecimals = VaultLogic.getAssetDecimals(swapAsset);

        // Calculating the notionalInSwapAsset is different because finalSpotPrice is always
        // in units of quote / base.
        if (dcsOptionType == DCSOptionType.BuyLow) {
            return
                (
                    (amountToConvert *
                        10 **
                            (swapAssetDecimals +
                                iOracleEntry.getTargetDecimals()))
                ) / (conversionPrice * 10 ** depositAssetDecimals);
        } else {
            return ((amountToConvert *
                conversionPrice *
                10 ** (swapAssetDecimals)) /
                (10 **
                    (depositAssetDecimals + iOracleEntry.getTargetDecimals())));
        }
    }

    function isSwapOccurring(
        uint256 finalSpotPrice,
        uint256 strikePrice,
        DCSOptionType dcsOptionType
    ) internal pure returns (bool) {
        if (dcsOptionType == DCSOptionType.BuyLow) {
            return finalSpotPrice < strikePrice;
        } else {
            return finalSpotPrice > strikePrice;
        }
    }

    function calculateVaultFinalPayoff(
        CegaGlobalStorage storage cgs,
        IAddressManager addressManager,
        address vaultAddress
    ) internal view returns (uint256) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        require(vault.vaultStatus == VaultStatus.TradeExpired, "500:WS");

        if (
            !dcsVault.isPayoffInDepositAsset &&
            dcsVault.settlementStatus != SettlementStatus.Settled
        ) {
            return
                convertDepositUnitsToSwap(
                    vault.totalAssets,
                    addressManager,
                    dcsVault.strikePrice,
                    getDCSProductDepositAsset(dcsProduct),
                    getDCSProductSwapAsset(dcsProduct),
                    dcsProduct.dcsOptionType
                );
        } else {
            // totalAssets already has totalYield included inside, because premium is paid upfront
            return vault.totalAssets;
        }
    }

    // MUTATIVE FUNCTIONS

    function processDepositQueue(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        uint256 maxProcessCount
    ) internal returns (uint256 processCount) {
        Vault storage vaultData = cgs.vaults[vaultAddress];
        uint32 productId = vaultData.productId;
        DCSProduct storage dcsProduct = cgs.dcsProducts[productId];

        require(
            vaultData.vaultStatus == VaultStatus.DepositsOpen,
            "400:DepositsClosed"
        );
        require(
            !(vaultData.totalAssets == 0 &&
                ICegaVault(vaultAddress).totalSupply() > 0),
            "500:Zombie"
        );

        DepositQueue storage queue = cgs.dcsDepositQueues[productId];
        uint256 queueLength = queue.depositors.length;
        processCount = Math.min(queueLength, maxProcessCount);
        uint128 totalDepositsAmount;

        uint256 totalSupply = ICegaVault(vaultAddress).totalSupply();
        uint256 totalAssets = VaultLogic.totalAssets(cgs, vaultAddress);
        uint8 depositAssetDecimals = VaultLogic.getAssetDecimals(
            getDCSProductDepositAsset(dcsProduct)
        );

        for (uint256 i = 0; i < processCount; i++) {
            address depositor = queue.depositors[queueLength - i - 1];
            uint128 depositAmount = queue.amounts[depositor];

            totalDepositsAmount += depositAmount;

            uint256 sharesAmount = VaultLogic.convertToShares(
                totalSupply,
                totalAssets,
                depositAssetDecimals,
                depositAmount
            );
            ICegaVault(vaultAddress).mint(depositor, sharesAmount);

            delete queue.amounts[depositor];
            queue.depositors.pop();

            emit DepositProcessed(vaultAddress, depositor, depositAmount);
        }

        queue.queuedDepositsTotalAmount -= totalDepositsAmount;

        dcsProduct.sumVaultUnderlyingAmounts += totalDepositsAmount;
        vaultData.totalAssets += totalDepositsAmount;

        if (processCount == queueLength) {
            VaultLogic.setVaultStatus(cgs, vaultAddress, VaultStatus.NotTraded);
        }
    }

    function processWithdrawalQueue(
        CegaGlobalStorage storage cgs,
        ITreasury treasury,
        IAddressManager addressManager,
        address vaultAddress,
        uint256 maxProcessCount
    ) internal returns (uint256 processCount) {
        require(
            VaultLogic.isWithdrawalPossible(cgs, vaultAddress),
            "400:WrongStatus"
        );

        Vault storage vaultData = cgs.vaults[vaultAddress];
        address settlementAsset = getVaultSettlementAsset(cgs, vaultAddress);
        uint256 totalAssets = vaultData.totalAssets;
        uint256 totalSupply = ICegaVault(vaultAddress).totalSupply();

        WithdrawalQueue storage queue = cgs.dcsWithdrawalQueues[vaultAddress];
        uint256 queueLength = queue.withdrawers.length;
        processCount = Math.min(queueLength, maxProcessCount);
        uint256 totalSharesWithdrawn;
        uint256 totalAssetsWithdrawn;

        for (uint256 i = 0; i < processCount; i++) {
            (uint256 sharesAmount, uint256 assetAmount) = processWithdrawal(
                queue,
                treasury,
                addressManager,
                vaultAddress,
                queueLength - i - 1,
                settlementAsset,
                totalAssets,
                totalSupply
            );
            totalSharesWithdrawn += sharesAmount;
            totalAssetsWithdrawn += assetAmount;
        }

        ICegaVault(vaultAddress).burn(vaultAddress, totalSharesWithdrawn);
        queue.queuedWithdrawalSharesAmount -= totalSharesWithdrawn;
        vaultData.totalAssets -= totalAssetsWithdrawn;

        if (cgs.dcsVaults[vaultAddress].isPayoffInDepositAsset) {
            cgs
                .dcsProducts[vaultData.productId]
                .sumVaultUnderlyingAmounts -= uint128(totalAssetsWithdrawn);
        }

        if (processCount == queueLength) {
            VaultLogic.setVaultStatus(
                cgs,
                vaultAddress,
                VaultStatus.WithdrawalQueueProcessed
            );
        }
    }

    function processWithdrawal(
        WithdrawalQueue storage queue,
        ITreasury treasury,
        IAddressManager addressManager,
        address vaultAddress,
        uint256 index,
        address settlementAsset,
        uint256 totalAssets,
        uint256 totalSupply
    ) private returns (uint256 sharesAmount, uint256 assetAmount) {
        Withdrawer memory withdrawer = queue.withdrawers[index];
        sharesAmount = queue.amounts[withdrawer.account][
            withdrawer.nextProductId
        ];

        assetAmount = VaultLogic.convertToAssets(
            totalSupply,
            totalAssets,
            sharesAmount
        );

        if (withdrawer.nextProductId == 0) {
            treasury.withdraw(settlementAsset, withdrawer.account, assetAmount);
        } else {
            redeposit(
                treasury,
                addressManager,
                settlementAsset,
                assetAmount,
                withdrawer.account,
                withdrawer.nextProductId
            );
        }

        emit WithdrawalProcessed(
            vaultAddress,
            sharesAmount,
            withdrawer.account,
            withdrawer.nextProductId
        );

        delete queue.amounts[withdrawer.account][withdrawer.nextProductId];
        queue.withdrawers.pop();
    }

    function redeposit(
        ITreasury treasury,
        IAddressManager addressManager,
        address asset,
        uint256 amount,
        address owner,
        uint32 nextProductId
    ) private {
        address redepositManager = addressManager.getRedepositManager();
        treasury.withdraw(asset, redepositManager, amount);
        IRedepositManager(redepositManager).redeposit(
            nextProductId,
            asset,
            uint128(amount), // Should we use safe conversion?
            owner
        );
    }

    function checkTradeExpiry(
        CegaGlobalStorage storage cgs,
        IAddressManager addressManager,
        address vaultAddress
    ) internal onlyValidVault(cgs, vaultAddress) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        require(
            dcsVault.settlementStatus != SettlementStatus.Defaulted,
            "Trade has defaulted already"
        );
        uint40 tenorInSeconds = dcsProduct.tenorInSeconds;

        uint256 currentTime = block.timestamp;
        if (currentTime <= vault.tradeStartDate + tenorInSeconds) {
            return;
        }
        VaultLogic.setVaultStatus(cgs, vaultAddress, VaultStatus.TradeExpired);

        uint256 finalSpotPrice = getSpotPriceAt(
            cgs,
            vaultAddress,
            addressManager,
            uint64(vault.tradeStartDate + tenorInSeconds)
        );

        if (
            isSwapOccurring(
                finalSpotPrice,
                dcsVault.strikePrice,
                dcsProduct.dcsOptionType
            )
        ) {
            VaultLogic.setIsPayoffInDepositAsset(cgs, vaultAddress, false);

            VaultLogic.setVaultSettlementStatus(
                cgs,
                vaultAddress,
                SettlementStatus.AwaitingSettlement
            );
        } else {
            VaultLogic.setVaultSettlementStatus(
                cgs,
                vaultAddress,
                SettlementStatus.Settled
            );
        }
    }

    function checkSettlementDefault(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal onlyValidVault(cgs, vaultAddress) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        if (
            block.timestamp >
            vault.tradeStartDate +
                dcsProduct.tenorInSeconds +
                (dcsProduct.daysToStartSettlementDefault * 1 days) &&
            dcsVault.settlementStatus == SettlementStatus.AwaitingSettlement
        ) {
            VaultLogic.setVaultSettlementStatus(
                cgs,
                vaultAddress,
                SettlementStatus.Defaulted
            );
        }
    }

    /// @notice Starts trade
    /// @param cgs Cega Global Storage
    /// @param vaultAddress Address of the vault to trade
    /// @param tradeWinnerNFT Address of the NFT to mint (0 to skip minting)
    function startTrade(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        address tradeWinnerNFT,
        ITreasury treasury,
        IAddressManager addressManager
    )
        internal
        onlyValidVault(cgs, vaultAddress)
        returns (uint256 nativeValueReceived, MMNFTMetadata memory nftMetadata)
    {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        uint40 tenorInSeconds = dcsProduct.tenorInSeconds;

        require(
            msg.sender == vault.auctionWinner,
            "Only auction winner can start the trade"
        );
        require(
            dcsVault.settlementStatus == SettlementStatus.Auctioned,
            "vault not auctioned yet"
        );
        require(!vault.isInDispute, "Vault is in dispute");

        require(!VaultLogic.getIsDefaulted(cgs, vaultAddress), "400:Defaulted");

        // Transfer the premium + any applicable late fee
        uint40 tradeStartDate = uint40(vault.tradeStartDate);
        address depositAsset = getDCSProductDepositAsset(dcsProduct);
        uint256 totalYield = VaultLogic.calculateCouponPayment(
            vault.totalAssets,
            vault.tradeStartDate,
            tenorInSeconds,
            dcsVault.aprBps,
            tradeStartDate + tenorInSeconds
        );
        dcsVault.totalYield = totalYield;
        uint256 lateFee = VaultLogic.calculateLateFee(
            dcsVault.totalYield,
            vault.tradeStartDate,
            dcsProduct.lateFeeBps,
            dcsProduct.daysToStartLateFees,
            dcsProduct.daysToStartAuctionDefault
        );
        // Send deposit to treasury, and late fee to fee recipient
        depositAsset.receiveTo(addressManager.getCegaFeeReceiver(), lateFee);
        nativeValueReceived = depositAsset.receiveTo(
            address(treasury),
            totalYield
        );
        // Late fee is not used for coupon payment or for user payouts
        vault.totalAssets += totalYield;
        dcsProduct.sumVaultUnderlyingAmounts += uint128(totalYield);

        VaultLogic.setVaultStatus(cgs, vaultAddress, VaultStatus.Traded);
        VaultLogic.setVaultSettlementStatus(
            cgs,
            vaultAddress,
            SettlementStatus.InitialPremiumPaid
        );

        nftMetadata = MMNFTMetadata({
            vaultAddress: vaultAddress,
            tradeStartDate: tradeStartDate,
            tradeEndDate: tradeStartDate + tenorInSeconds
        });

        if (tradeWinnerNFT != address(0)) {
            uint256 tokenId = ITradeWinnerNFT(tradeWinnerNFT).mint(
                msg.sender,
                nftMetadata
            );
            vault.auctionWinnerTokenId = tokenId;
        }
    }

    function checkAuctionDefault(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal onlyValidVault(cgs, vaultAddress) {
        bool isDefaulted = VaultLogic.getIsDefaulted(cgs, vaultAddress);
        if (isDefaulted) {
            VaultLogic.setVaultSettlementStatus(
                cgs,
                vaultAddress,
                SettlementStatus.Defaulted
            );
        }
    }

    function settleVault(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        ITreasury treasury,
        IAddressManager addressManager
    )
        internal
        onlyValidVault(cgs, vaultAddress)
        returns (uint256 nativeValueReceived)
    {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        require(!vault.isInDispute, "trade in dipsute");

        require(vault.auctionWinnerTokenId != 0, "Vault has no auction winner");
        require(
            msg.sender ==
                IERC721AUpgradeable(addressManager.getTradeWinnerNFT()).ownerOf(
                    vault.auctionWinnerTokenId
                ),
            "Only NFT holder can settle vault"
        );
        require(
            dcsVault.isPayoffInDepositAsset == false,
            "Expired OTM. No settlement needed"
        );

        checkSettlementDefault(cgs, vaultAddress);

        require(
            dcsVault.settlementStatus == SettlementStatus.AwaitingSettlement,
            "Not AwaitingSettlement"
        );

        address depositAsset = getDCSProductDepositAsset(dcsProduct);
        address swapAsset = getDCSProductSwapAsset(dcsProduct);

        // First, transfer all of the deposit asset (deposits + coupon) to the nftHolder...
        uint256 totalAssets = vault.totalAssets;
        treasury.withdraw(depositAsset, msg.sender, totalAssets);
        dcsProduct.sumVaultUnderlyingAmounts -= uint128(totalAssets);

        // Then, get the finalPayoff (converted total assets) in swapAsset back from the nftHolder
        uint256 convertedTotalAssets = convertDepositUnitsToSwap(
            vault.totalAssets,
            addressManager,
            dcsVault.strikePrice,
            depositAsset,
            swapAsset,
            dcsProduct.dcsOptionType
        );
        nativeValueReceived = swapAsset.receiveTo(
            address(treasury),
            convertedTotalAssets
        );

        // Now that we've used totalAssets for depositAsset math, we need to convert every unit into swapAssets
        vault.totalAssets = convertedTotalAssets;
        dcsVault.totalYield = convertDepositUnitsToSwap(
            dcsVault.totalYield,
            addressManager,
            dcsVault.strikePrice,
            depositAsset,
            swapAsset,
            dcsProduct.dcsOptionType
        );

        VaultLogic.setVaultSettlementStatus(
            cgs,
            vaultAddress,
            SettlementStatus.Settled
        );
    }

    function collectVaultFees(
        CegaGlobalStorage storage cgs,
        ITreasury treasury,
        IAddressManager addressManager,
        address vaultAddress
    ) internal {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        require(vault.vaultStatus == VaultStatus.TradeExpired, "500:WS");
        require(
            dcsVault.settlementStatus == SettlementStatus.Settled,
            "500:WS"
        );

        require(!vault.isInDispute, "trade in dipsute");

        (uint256 totalFees, , ) = VaultLogic.calculateFees(cgs, vaultAddress);
        address settlementAsset = getVaultSettlementAsset(cgs, vaultAddress);

        VaultLogic.setVaultStatus(cgs, vaultAddress, VaultStatus.FeesCollected);
        vault.totalAssets -= totalFees;

        treasury.withdraw(
            settlementAsset,
            addressManager.getCegaFeeReceiver(),
            totalFees
        );

        if (dcsVault.isPayoffInDepositAsset) {
            dcsProduct.sumVaultUnderlyingAmounts -= uint128(totalFees);
        }
    }
}

