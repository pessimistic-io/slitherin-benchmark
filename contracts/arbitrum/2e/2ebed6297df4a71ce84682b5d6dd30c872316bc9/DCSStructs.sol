// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

enum DCSOptionType {
    BuyLow,
    SellHigh
}

enum SettlementStatus {
    NotAuctioned,
    Auctioned,
    InitialPremiumPaid,
    AwaitingSettlement,
    Settled,
    Defaulted
}

struct DCSProductCreationParams {
    uint128 maxDepositAmountLimit;
    uint128 minDepositAmount;
    uint128 minWithdrawalAmount;
    address quoteAssetAddress;
    address baseAssetAddress;
    DCSOptionType dcsOptionType;
    uint8 daysToStartLateFees;
    uint8 daysToStartAuctionDefault;
    uint8 daysToStartSettlementDefault;
    uint16 lateFeeBps;
    uint16 strikeBarrierBps;
    uint40 tenorInSeconds;
    uint8 disputePeriodInHours;
}

struct DCSProduct {
    uint32 id;
    bool isDepositQueueOpen;
    uint128 maxDepositAmountLimit;
    uint128 minDepositAmount;
    uint128 minWithdrawalAmount;
    uint128 sumVaultUnderlyingAmounts; //revisit later
    address[] vaults;
    DCSOptionType dcsOptionType;
    address quoteAssetAddress; // should be immutable
    address baseAssetAddress; // should be immutable
    uint8 daysToStartLateFees;
    uint8 daysToStartAuctionDefault;
    uint8 daysToStartSettlementDefault;
    uint16 lateFeeBps;
    uint16 strikeBarrierBps;
    uint40 tenorInSeconds;
    uint8 disputePeriodInHours;
}

struct DCSVault {
    SettlementStatus settlementStatus;
    bool isPayoffInDepositAsset;
    uint256 aprBps;
    uint256 initialSpotPrice;
    uint256 strikePrice;
    uint256 totalYield;
}

