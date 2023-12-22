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

    event CollectRewards(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 indexed liquidityNftId,
        uint256 rewardToken0Amount,
        uint256 rewardToken1Amount,
        uint256 rewardUsdtAmount
    );

    event EarnPreparation(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 indexed liquidityNftId,
        uint256 rewardUsdtAmount,
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
        uint256 allocatedUsdtAmount,
        uint256 remainingUsdtAmount
    );

    event Rescale(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 dustToken0Amount,
        uint256 dustToken1Amount
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

