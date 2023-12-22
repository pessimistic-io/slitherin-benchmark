// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IStfxStorage {
    /// @notice Enum to describe the trading status of the vault
    /// @dev NOT_OPENED - Not open
    /// @dev OPENED - opened position
    /// @dev CLOSED - closed position
    /// @dev LIQUIDATED - liquidated position
    /// @dev CANCELLED - did not start due to deadline reached
    /// @dev DISTRIBUTED - distributed fees
    enum StfStatus {
        NOT_OPENED,
        OPENED,
        CLOSED,
        LIQUIDATED,
        CANCELLED,
        DISTRIBUTED
    }

    struct Dex {
        address vault;
        address marketRegistry;
        address clearingHouse;
    }

    struct Stf {
        address baseToken;
        bool tradeDirection;
        uint256 fundraisingPeriod;
        uint256 entryPrice;
        uint256 targetPrice;
        uint256 liquidationPrice;
        uint256 leverage;
    }

    struct StfInfo {
        address stfxAddress;
        address manager;
        uint256 totalRaised;
        uint256 remainingAmountAfterClose;
        uint256 endTime;
        uint256 fundDeadline;
        StfStatus status;
        mapping(address => uint256) userAmount;
        mapping(address => uint256) claimAmount;
        mapping(address => bool) claimed;
    }
}

