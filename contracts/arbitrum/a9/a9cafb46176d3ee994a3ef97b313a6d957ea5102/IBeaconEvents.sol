// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IBeaconEvents {
    enum TradeType {
        Trade,
        Liquidation
    }

    event Trade(
        bytes32 indexed pair,
        uint256 indexed accountId,
        uint256 indexed liquidityPoolId,
        address accountUser,
        int256 price,
        int256 size,
        uint256 marginFee,
        TradeType tradeType
    );

    event Deposit(
        uint256 indexed accountId,
        address indexed accountUser,
        address indexed token,
        uint256 amount
    );

    struct PositionFee {
        uint256 accountId;
        bytes32 pair;
        uint256 liquidityPoolId;
        int256 amount;
        uint256 timestamp;
    }

    event CollectBorrowFees(PositionFee[] fees);
    event CollectFundingFees(PositionFee[] fees);
}

