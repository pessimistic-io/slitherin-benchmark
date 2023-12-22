// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

library DCATypes {
    enum ExecutionPhase {
        COLLECT,
        EXCHANGE,
        DISTRIBUTE,
        FINISH
    }

    struct PoolExecutionData {
        bool isExecuting;
        ExecutionPhase currentPhase;
        int256 lastLoopIndex;
        uint256 totalCollectedToExchange;
        uint256 totalCollectedFee;
        uint256 received;
    }

    struct PoolData {
        address investingAsset;
        address targetAsset;
        address accessManager;
        uint256 investedAmount;
        uint256 accumulatedAmount;
        uint256 poolFee; // percentage amount divided by 1000000
        uint24 uniswapFeeTier; // 3000 for 0.3% https://docs.uniswap.org/protocol/concepts/V3-overview/fees#pool-fees-tiers
        uint256 maxParticipants;
        uint256 minWeeklyInvestment;
        uint256 lastExecuted;
        PoolExecutionData executionData;
    }

    struct UserPoolData {
        uint256 investedAmount; // how much investingAsset already collected by this pool by this user in total
        uint256 receivedAmount; // how much targetAsset user has already received to his wallet
        uint256 lastExchangeAmount; // how much investingAsset has been exchanged in last strategy execution
        uint256 investedAmountSinceStart; // how many investingAsset already collected by this pool since start timestamp
        uint256 start; // from when calculate toInvest amount
        uint256 weeklyInvestment; // how much targetAsset are you willing to invest within a week (7 days)
        bool participating; // is currently participating
        uint256 participantsIndex; // index in poolParticipants array
    }

    struct GetPoolsInfoResponse {
        address investingAsset;
        address targetAsset;
        uint256 investedAmount;
        uint256 accumulatedAmount;
        uint256 poolFee; // percentage amount divided by 1000000
        uint24 uniswapFeeTier; // 3000 for 0.3% https://docs.uniswap.org/protocol/concepts/V3-overview/fees#pool-fees-tiers
        uint256 maxParticipants;
        uint256 minWeeklyInvestment;
        uint256 lastExecuted;
        bool isExecuting;
        uint256 participantsAmount;
        DCATypes.UserPoolData userPoolData;
    }
}

