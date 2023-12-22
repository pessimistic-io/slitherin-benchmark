// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./Perp.sol";
import "./InterestRateModel.sol";

library DataType {
    struct GlobalData {
        uint256 pairGroupsCount;
        uint256 pairsCount;
        uint256 vaultCount;
        mapping(uint256 => DataType.PairGroup) pairGroups;
        mapping(uint256 => DataType.PairStatus) pairs;
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) rebalanceFeeGrowthCache;
        mapping(uint256 => DataType.Vault) vaults;
        /// @dev account -> pairGroupId -> vaultId
        mapping(address => mapping(uint256 => DataType.OwnVaults)) ownVaultsMap;
    }

    struct PairGroup {
        uint256 id;
        address stableTokenAddress;
        uint8 marginRoundedDecimal;
    }

    struct OwnVaults {
        uint256 mainVaultId;
        uint256[] isolatedVaultIds;
    }

    struct AddPairParams {
        uint256 pairGroupId;
        address uniswapPool;
        bool isIsolatedMode;
        DataType.AssetRiskParams assetRiskParams;
        InterestRateModel.IRMParams stableIrmParams;
        InterestRateModel.IRMParams underlyingIrmParams;
    }

    struct AssetRiskParams {
        uint256 riskRatio;
        int24 rangeSize;
        int24 rebalanceThreshold;
    }

    struct PairStatus {
        uint256 id;
        uint256 pairGroupId;
        AssetPoolStatus stablePool;
        AssetPoolStatus underlyingPool;
        AssetRiskParams riskParams;
        Perp.SqrtPerpAssetStatus sqrtAssetStatus;
        bool isMarginZero;
        bool isIsolatedMode;
        uint256 lastUpdateTimestamp;
    }

    struct AssetPoolStatus {
        address token;
        address supplyTokenAddress;
        ScaledAsset.TokenStatus tokenStatus;
        InterestRateModel.IRMParams irmParams;
    }

    struct Vault {
        uint256 id;
        uint256 pairGroupId;
        address owner;
        int256 margin;
        bool autoTransferDisabled;
        Perp.UserStatus[] openPositions;
    }

    struct RebalanceFeeGrowthCache {
        int256 stableGrowth;
        int256 underlyingGrowth;
    }

    struct TradeResult {
        Perp.Payoff payoff;
        int256 fee;
        int256 minDeposit;
    }

    struct SubVaultStatusResult {
        uint256 pairId;
        Perp.UserStatus position;
        int256 delta;
        int256 unrealizedFee;
    }

    struct VaultStatusResult {
        uint256 vaultId;
        int256 vaultValue;
        int256 margin;
        int256 positionValue;
        int256 minDeposit;
        SubVaultStatusResult[] subVaults;
    }
}

