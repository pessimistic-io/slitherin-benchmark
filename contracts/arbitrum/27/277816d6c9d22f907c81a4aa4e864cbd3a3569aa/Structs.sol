// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { DCSProduct, DCSVault } from "./DCSStructs.sol";
import { IOracleEntry } from "./IOracleEntry.sol";

uint32 constant DCS_STRATEGY_ID = 1;

struct DepositQueue {
    uint128 queuedDepositsTotalAmount;
    mapping(address => uint128) amounts;
    address[] depositors;
}

struct Withdrawer {
    address account;
    uint32 nextProductId;
}

struct WithdrawalQueue {
    uint256 queuedWithdrawalSharesAmount;
    mapping(address => mapping(uint32 => uint256)) amounts;
    Withdrawer[] withdrawers;
}

struct CegaGlobalStorage {
    // Global information
    uint32 strategyIdCounter;
    uint32 productIdCounter;
    uint32[] strategyIds;
    mapping(uint32 => uint32) strategyOfProduct;
    mapping(address => Vault) vaults;
    // DCS information
    mapping(uint32 => DCSProduct) dcsProducts;
    mapping(uint32 => DepositQueue) dcsDepositQueues;
    mapping(address => DCSVault) dcsVaults;
    mapping(address => WithdrawalQueue) dcsWithdrawalQueues;
    // vaultAddress => (timestamp => price)
    mapping(address => mapping(uint64 => uint256)) oraclePriceOverride;
}

struct Vault {
    uint32 productId;
    uint256 yieldFeeBps;
    uint256 managementFeeBps;
    uint256 vaultStartDate;
    uint40 tradeStartDate;
    address auctionWinner;
    address underlyingAsset;
    uint256 totalAssets;
    VaultStatus vaultStatus;
    uint256 auctionWinnerTokenId;
    IOracleEntry.DataSource dataSource;
    bool isInDispute;
}

enum VaultStatus {
    DepositsClosed,
    DepositsOpen,
    NotTraded,
    Traded,
    TradeExpired,
    FeesCollected,
    WithdrawalQueueProcessed,
    Zombie
}

struct MMNFTMetadata {
    address vaultAddress;
    uint40 tradeStartDate;
    uint40 tradeEndDate;
}

