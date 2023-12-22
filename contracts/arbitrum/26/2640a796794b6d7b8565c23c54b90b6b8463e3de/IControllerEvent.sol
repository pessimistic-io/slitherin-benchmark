// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IControllerEvent {
    event SetTransactionDeadlineDuration(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 transactionDeadlineDuration
    );

    event SetTickSpreadUpper(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 tickSpreadUpper
    );

    event SetTickSpreadLower(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 tickSpreadLower
    );

    event SetTickGapUpper(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 tickGapUpper
    );

    event SetTickGapLower(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 tickGapLower
    );

    event SetBuyBackToken(
        address indexed strategyContract,
        address indexed executorAddress,
        address buyBackToken
    );

    event SetBuyBackNumerator(
        address indexed strategyContract,
        address indexed executorAddress,
        uint24 buyBackNumerator
    );

    event SetFundManagerVaultByIndex(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 index,
        address fundManagerVaultAddress,
        uint24 fundManagerProfitVaultNumerator
    );

    event SetFundManagerByIndex(
        address indexed fundManagerVaultAddress,
        address indexed executorAddress,
        uint256 index,
        address fundManagerAddress,
        uint24 fundManagerProfitNumerator
    );

    event SetEarnLoopSegmentSize(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 earnLoopSegmentSize
    );

    event SetTickBoundaryOffset(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 tickBoundaryOffset
    );

    event SetRescaleTickBoundaryOffset(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 rescaleTickBoundaryOffset
    );

    event SetRescaleTickTolerance(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 rescaleTickTolerance
    );

    event CollectRewards(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 indexed liquidityNftId,
        uint256 rewardToken0Amount,
        uint256 rewardToken1Amount,
        uint256 rewardWbtcAmount
    );

    event EarnPreparation(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 indexed liquidityNftId,
        uint256 rewardWbtcAmount,
        uint256 remainingEarnCountDown
    );

    event Earn(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 indexed liquidityNftId,
        uint256 remainingEarnCountDown
    );

    event Allocate(
        address indexed fundManagerVaultAddress,
        address indexed executorAddress,
        uint256 allocatedWbtcAmount,
        uint256 remainingWbtcAmount
    );

    event RescaleStart(
        address indexed strategyContract,
        address indexed executorAddress,
        bool wasInRange,
        int24 tickSpacing,
        int24 tickGapUpper,
        int24 tickGapLower,
        int24 tickBoundaryOffset,
        int24 lastRescaleTick,
        int24 tickBeforeRescale,
        int24 thisRescaleTick,
        int24 originalTickUpper,
        int24 originalTickLower
    );

    event RescaleEnd(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 dustToken0Amount,
        uint256 dustToken1Amount,
        int24 tickSpacing,
        int24 thisRescaleTick,
        int24 tickSpreadUpper,
        int24 tickSpreadLower,
        int24 rescaleTickBoundaryOffset,
        int24 newTickUpper,
        int24 newTickLower
    );

    event DepositDustToken(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 indexed liquidityNftId,
        bool depositDustToken0,
        uint256 increasedToken0Amount,
        uint256 increasedToken1Amount,
        uint256 dustToken0Amount,
        uint256 dustToken1Amount
    );
}

