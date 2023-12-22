// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IControllerEvent {
    event SetTransactionDeadlineDuration(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 transactionDeadlineDuration
    );

    event SetTickSpread(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 tickSpread
    );

    event SetTickEndurance(
        address indexed strategyContract,
        address indexed executorAddress,
        int24 tickEndurance
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

    event SetFundManagerByIndex(
        address indexed strategyContract,
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

    event SetMaxToken0ToToken1SwapAmount(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 maxToken0ToToken1SwapAmount
    );

    event SetMaxToken1ToToken0SwapAmount(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 maxToken1ToToken0SwapAmount
    );

    event SetMinSwapTimeInterval(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 minSwapTimeInterval
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

    event RescalePreparation(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 dustToken0Amount,
        uint256 dustToken1Amount,
        bool swapToken0ToToken1,
        uint256 remainingSwapAmount,
        uint256 remainingRescaleCountDown
    );

    event Rescale(
        address indexed strategyContract,
        address indexed executorAddress,
        uint256 dustToken0Amount,
        uint256 dustToken1Amount,
        uint256 swapTimeStamp,
        bool swapToken0ToToken1,
        uint256 remainingSwapAmount,
        uint256 remainingRescaleCountDown
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

