// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./Constant.sol";

interface IDashboard {
    struct VaultData {
        uint256 totalCirculation;
        uint256 totalLockedGrv;
        uint256 totalVeGrv;
        uint256 averageLockDuration;
        uint256 accruedGrv;
        uint256 claimedGrv;
        uint256[] thisWeekRebatePoolAmounts;
        address[] thisWeekRebatePoolMarkets;
        uint256 thisWeekRebatePoolValue;
        Constant.EcoZone ecoZone;
        uint256 claimTax;
        uint256 ppt;
        uint256 ecoDR;
        uint256 lockedBalance;
        uint256 lockDuration;
        uint256 firstLockTime;
        uint256 myVeGrv;
        uint256 vp;
        RebateData rebateData;
    }

    struct RebateData {
        uint256 weeklyProfit;
        uint256 unClaimedRebateValue;
        address[] unClaimedMarkets;
        uint256[] unClaimedRebatesAmount;
        uint256 claimedRebateValue;
        address[] claimedMarkets;
        uint256[] claimedRebatesAmount;
    }
    struct CompoundData {
        ExpectedTaxData taxData;
        ExpectedEcoScoreData ecoScoreData;
        ExpectedVeGrv veGrvData;
        BoostedAprData boostedAprData;
        uint256 accruedGrv;
        uint256 lockDuration;
        uint256 nextLockDuration;
    }

    struct LockData {
        ExpectedEcoScoreData ecoScoreData;
        ExpectedVeGrv veGrvData;
        BoostedAprData boostedAprData;
        uint256 lockedGrv;
        uint256 lockDuration;
        uint256 nextLockDuration;
    }

    struct ClaimData {
        ExpectedEcoScoreData ecoScoreData;
        ExpectedTaxData taxData;
        uint256 accruedGrv;
    }

    struct ExpectedTaxData {
        uint256 prevPPTRate;
        uint256 nextPPTRate;
        uint256 prevClaimTaxRate;
        uint256 nextClaimTaxRate;
        uint256 discountTaxRate;
        uint256 afterTaxesGrv;
    }

    struct ExpectedEcoScoreData {
        Constant.EcoZone prevEcoZone;
        Constant.EcoZone nextEcoZone;
        uint256 prevEcoDR;
        uint256 nextEcoDR;
    }

    struct ExpectedVeGrv {
        uint256 prevVeGrv;
        uint256 prevVotingPower;
        uint256 nextVeGrv;
        uint256 nextVotingPower;
        uint256 nextWeeklyRebate;
        uint256 prevWeeklyRebate;
    }

    struct BoostedAprParams {
        address account;
        uint256 amount;
        uint256 expiry;
        Constant.EcoScorePreviewOption option;
    }

    struct BoostedAprData {
        BoostedAprDetails[] boostedAprDetailList;
    }
    struct BoostedAprDetails {
        address market;
        uint256 currentSupplyApr;
        uint256 currentBorrowApr;
        uint256 expectedSupplyApr;
        uint256 expectedBorrowApr;
    }

    function getCurrentGRVPrice() external view returns (uint256);
    function getVaultInfo(address account) external view returns (VaultData memory);
    function getLockUnclaimedGrvModalInfo(address account) external view returns (CompoundData memory);

    function getInitialLockUnclaimedGrvModalInfo(
        address account,
        uint256 expiry
    ) external view returns (CompoundData memory);

    function getLockModalInfo(
        address account,
        uint256 amount,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view returns (LockData memory);

    function getClaimModalInfo(address account) external view returns (ClaimData memory);
}

