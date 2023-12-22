// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.9;

library DataTypes {
    struct LPAmountInfo {
        uint256 amount;
        uint256 initValue;
        address lPAddress;
        uint256 createTime;
        uint256 reservationTime;
        uint256 purchaseHeightInfo;
    }

    struct HedgeTreatmentInfo {
        bool isSell;
        address token;
        uint256 amount;
    }

    struct LPPendingInit {
        uint256 amount;
        address lPAddress;
        uint256 createTime;
        uint256 purchaseHeightInfo;
    }

    struct PositionDetails {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        int256 unrealisedPnl;
        uint256 lastIncreasedTime;
        bool isLong;
        bool hasUnrealisedProfit;
    }

    struct IncreaseHedgingPool {
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 sizeDelta;
        uint256 acceptablePrice;
    }

    struct DecreaseHedgingPool {
        address[] path;
        address indexToken;
        uint256 sizeDelta;
        uint256 acceptablePrice;
        uint256 collateralDelta;
    }

    struct HedgingAggregatorInfo {
        uint256 customerId;
        uint256 productId;
        uint256 amount;
        uint256 releaseHeight;
    }

    enum TransferHelperStatus {
        TOTHIS,
        TOLP,
        TOGMX,
        TOCDXCORE,
        TOMANAGE,
        GUARDIANW
    }

    struct Hedging {
        bool isSell;
        address token;
        uint256 amount;
        uint256 releaseHeight;
    }
}

