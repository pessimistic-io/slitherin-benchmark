// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { Math } from "./Math.sol";
import {     IERC20Metadata,     IERC20 } from "./IERC20Metadata.sol";
import { IERC721 } from "./IERC721.sol";

import {     CegaGlobalStorage,     Vault,     VaultStatus,     MMNFTMetadata } from "./Structs.sol";
import {     DCSProduct,     DCSVault,     SettlementStatus,     DCSOptionType } from "./DCSStructs.sol";
import {     IOracleEntry } from "./IOracleEntry.sol";
import { IAddressManager } from "./IAddressManager.sol";

library VaultLogic {
    // CONSTANTS

    uint256 internal constant DAYS_IN_YEAR = 365;

    uint256 internal constant BPS_DECIMALS = 1E4;

    uint256 internal constant LARGE_CONSTANT = 1E18;

    uint8 internal constant VAULT_DECIMALS = 18;

    uint8 internal constant NATIVE_ASSET_DECIMALS = 18;

    // EVENTS

    event VaultStatusUpdated(
        address indexed vaultAddress,
        VaultStatus vaultStatus
    );

    event SettlementStatusUpdated(
        address indexed vaultAddress,
        SettlementStatus settlementStatus
    );

    event IsPayoffInDepositAssetUpdated(
        address indexed vaultAddress,
        bool isPayoffInDepositAsset
    );

    event DisputeSubmitted(address indexed vaultAddress);

    event DisputeProcessed(
        address indexed vaultAddress,
        bool isDisputeAccepted,
        uint256 timestamp,
        uint256 newPrice
    );

    event OraclePriceOverriden(
        address indexed vaultAddress,
        uint256 timestamp,
        uint256 newPrice
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

    function totalAssets(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal view returns (uint256) {
        return cgs.vaults[vaultAddress].totalAssets;
    }

    function convertToAssets(
        uint256 _totalSupply,
        uint256 _totalAssets,
        uint256 _shares
    ) internal pure returns (uint256) {
        // assumption: all assets we support have <= 18 decimals
        return (_shares * _totalAssets) / _totalSupply;
    }

    function convertToAssets(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        uint256 shares
    ) internal view returns (uint256) {
        uint256 _totalSupply = IERC20(vaultAddress).totalSupply();

        if (_totalSupply == 0) return 0;
        // assumption: all assets we support have <= 18 decimals
        // shares and _totalSupply have 18 decimals
        return (shares * totalAssets(cgs, vaultAddress)) / _totalSupply;
    }

    function convertToShares(
        uint256 _totalSupply,
        uint256 _totalAssets,
        uint8 _depositAssetDecimals,
        uint256 assets
    ) internal pure returns (uint256) {
        if (_totalAssets == 0 || _totalSupply == 0) {
            return assets * 10 ** (VAULT_DECIMALS - _depositAssetDecimals);
        } else {
            // _totalSupply has 18 decimals, assets and _totalAssets have the same decimals
            return (assets * _totalSupply) / (_totalAssets);
        }
    }

    function convertToShares(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        uint256 assets
    ) internal view returns (uint256) {
        uint256 _totalSupply = IERC20(vaultAddress).totalSupply();
        uint256 _totalAssets = totalAssets(cgs, vaultAddress);

        Vault storage vault = cgs.vaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        uint8 _depositAssetDecimals = getAssetDecimals(
            getProductDepositAsset(dcsProduct)
        );

        return
            convertToShares(
                _totalSupply,
                _totalAssets,
                _depositAssetDecimals,
                assets
            );
    }

    function getAssetDecimals(address asset) internal view returns (uint8) {
        return
            asset == address(0)
                ? NATIVE_ASSET_DECIMALS
                : IERC20Metadata(asset).decimals();
    }

    /**
     * @notice Calculates the coupon payment accumulated from block.timestamp
     * @param cgs CegaGlobalStorage
     * @param vaultAddress address of vault
     */
    function getCurrentYield(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        uint256 endDate
    ) internal view returns (uint256) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];

        return
            calculateCouponPayment(
                vault.totalAssets - dcsVault.totalYield,
                vault.tradeStartDate,
                dcsProduct.tenorInSeconds,
                dcsVault.aprBps,
                endDate
            );
    }

    function calculateCouponPayment(
        uint256 underlyingAmount,
        uint256 tradeStartDate,
        uint256 tenorInSeconds,
        uint256 aprBps,
        uint256 endDate
    ) internal pure returns (uint256) {
        uint256 secondsPassed = endDate - tradeStartDate;
        uint256 couponSeconds = Math.min(secondsPassed, tenorInSeconds);
        return
            (underlyingAmount * couponSeconds * aprBps * LARGE_CONSTANT) /
            (DAYS_IN_YEAR * BPS_DECIMALS * LARGE_CONSTANT * 1 days);
    }

    function calculateLateFee(
        uint256 coupon,
        uint256 startDate,
        uint256 lateFeeBps,
        uint256 daysToStartLateFees,
        uint256 daysToStartAuctionDefault
    ) internal view returns (uint256) {
        uint256 daysLate = getDaysLate(startDate);
        if (daysLate < daysToStartLateFees) {
            return 0;
        } else {
            if (daysLate >= daysToStartAuctionDefault) {
                daysLate = daysToStartAuctionDefault;
            }
            return (daysLate * coupon * lateFeeBps) / (BPS_DECIMALS);
        }
    }

    function getIsDefaulted(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal view returns (bool) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        if (dcsVault.settlementStatus != SettlementStatus.Auctioned) {
            return false;
        }
        uint256 startDate = cgs.vaults[vaultAddress].tradeStartDate;
        uint256 daysLate = getDaysLate(startDate);
        return daysLate >= dcsProduct.daysToStartAuctionDefault;
    }

    function getDaysLate(uint256 startDate) internal view returns (uint256) {
        uint256 secondsLate = block.timestamp - startDate;
        uint256 daysLate = secondsLate / 1 days;
        return daysLate;
    }

    function isWithdrawalPossible(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal view returns (bool) {
        VaultStatus vaultStatus = cgs.vaults[vaultAddress].vaultStatus;
        SettlementStatus settlementStatus = cgs
            .dcsVaults[vaultAddress]
            .settlementStatus;
        return
            vaultStatus == VaultStatus.FeesCollected ||
            vaultStatus == VaultStatus.Zombie ||
            settlementStatus == SettlementStatus.Defaulted;
    }

    // Duplicates DCSProductEntry.sol
    function getProductDepositAsset(
        DCSProduct storage dcsProduct
    ) internal view returns (address) {
        return
            dcsProduct.dcsOptionType == DCSOptionType.BuyLow
                ? dcsProduct.quoteAssetAddress
                : dcsProduct.baseAssetAddress;
    }

    // MUTATIVE FUNCTIONS

    function setVaultStatus(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        VaultStatus status
    ) internal onlyValidVault(cgs, vaultAddress) {
        cgs.vaults[vaultAddress].vaultStatus = status;

        emit VaultStatusUpdated(vaultAddress, status);
    }

    function setVaultSettlementStatus(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        SettlementStatus status
    ) internal {
        cgs.dcsVaults[vaultAddress].settlementStatus = status;

        emit SettlementStatusUpdated(vaultAddress, status);
    }

    function setIsPayoffInDepositAsset(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        bool value
    ) internal {
        cgs.dcsVaults[vaultAddress].isPayoffInDepositAsset = value;
        emit IsPayoffInDepositAssetUpdated(vaultAddress, value);
    }

    function openVaultDeposits(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal onlyValidVault(cgs, vaultAddress) {
        require(
            cgs.vaults[vaultAddress].vaultStatus == VaultStatus.DepositsClosed,
            "500:WS"
        );
        setVaultStatus(cgs, vaultAddress, VaultStatus.DepositsOpen);
    }

    function rolloverVault(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal onlyValidVault(cgs, vaultAddress) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];

        require(
            vault.vaultStatus == VaultStatus.WithdrawalQueueProcessed,
            "500:WS"
        );
        uint256 tradeEndDate = vault.tradeStartDate + dcsProduct.tenorInSeconds;

        require(tradeEndDate != 0, "400:TE");

        if (cgs.dcsVaults[vaultAddress].isPayoffInDepositAsset) {
            vault.vaultStartDate = tradeEndDate;
            vault.tradeStartDate = 0;
            vault.auctionWinner = address(0);
            vault.auctionWinnerTokenId = 0;

            dcsVault.aprBps = 0;
            dcsVault.initialSpotPrice = 0;
            dcsVault.strikePrice = 0;
            setVaultStatus(cgs, vaultAddress, VaultStatus.DepositsClosed);
            setVaultSettlementStatus(
                cgs,
                vaultAddress,
                SettlementStatus.NotAuctioned
            );
        } else {
            setVaultStatus(cgs, vaultAddress, VaultStatus.Zombie);
        }
    }

    function calculateFees(
        CegaGlobalStorage storage cgs,
        address vaultAddress
    ) internal view returns (uint256, uint256, uint256) {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vault.productId];

        uint256 totalYield = dcsVault.totalYield;
        uint256 underlyingAmount = vault.totalAssets - totalYield;
        uint256 managementFee = (underlyingAmount *
            dcsProduct.tenorInSeconds *
            vault.managementFeeBps) / (365 days * BPS_DECIMALS);
        uint256 yieldFee = (totalYield * vault.yieldFeeBps) / BPS_DECIMALS;
        uint256 totalFee = managementFee + yieldFee;

        return (totalFee, managementFee, yieldFee);
    }

    function disputeVault(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        address tradeWinnerNFT
    ) internal {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];
        DCSProduct storage product = cgs.dcsProducts[vault.productId];

        uint256 tradeStartDate = vault.tradeStartDate;
        uint256 tradeEndDate = vault.tradeStartDate + product.tenorInSeconds;
        uint256 currentTime = block.timestamp;
        VaultStatus vaultStatus = vault.vaultStatus;

        require(!vault.isInDispute, "Vault already in dispute");

        if (currentTime < tradeEndDate) {
            require(msg.sender == vault.auctionWinner, "Not Auction Winner");

            require(
                currentTime > tradeStartDate &&
                    currentTime <
                    tradeStartDate + (product.disputePeriodInHours * 1 hours),
                "Outside of dispute window"
            );
            require(
                vaultStatus == VaultStatus.NotTraded,
                "Invalid vault status"
            );
        } else {
            require(
                msg.sender ==
                    IERC721(tradeWinnerNFT).ownerOf(vault.auctionWinnerTokenId),
                "Not Auction Winner"
            );
            require(
                currentTime <
                    tradeEndDate + (product.disputePeriodInHours * 1 hours),
                "Outside of dispute window"
            );
            require(
                vaultStatus == VaultStatus.TradeExpired,
                "Invalid vault status"
            );

            // if the vault converted and the MM already settled
            if (dcsVault.isPayoffInDepositAsset == false) {
                require(
                    dcsVault.settlementStatus != SettlementStatus.Settled,
                    "Cant dispute after settlement"
                );
            }
        }

        vault.isInDispute = true;

        emit DisputeSubmitted(vaultAddress);
    }

    function processDispute(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        uint256 newPrice
    ) internal {
        Vault storage vault = cgs.vaults[vaultAddress];
        DCSProduct storage product = cgs.dcsProducts[vault.productId];
        DCSVault storage dcsVault = cgs.dcsVaults[vaultAddress];

        require(vault.isInDispute, "Vault is not in dispute");

        uint64 timestamp;

        if (newPrice != 0) {
            VaultStatus vaultStatus = vault.vaultStatus;

            if (vaultStatus == VaultStatus.NotTraded) {
                timestamp = vault.tradeStartDate;
            } else {
                timestamp = vault.tradeStartDate + product.tenorInSeconds;

                setVaultSettlementStatus(
                    cgs,
                    vaultAddress,
                    SettlementStatus.AwaitingSettlement
                );

                setIsPayoffInDepositAsset(cgs, vaultAddress, true);
            }

            overrideOraclePrice(cgs, vaultAddress, timestamp, newPrice);
        }

        vault.isInDispute = false;

        emit DisputeProcessed(vaultAddress, newPrice != 0, timestamp, newPrice);
    }

    function overrideOraclePrice(
        CegaGlobalStorage storage cgs,
        address vaultAddress,
        uint64 timestamp,
        uint256 newPrice
    ) internal {
        require(newPrice != 0, "Invalid price");

        cgs.oraclePriceOverride[vaultAddress][timestamp] = newPrice;

        emit OraclePriceOverriden(vaultAddress, timestamp, newPrice);
    }
}

