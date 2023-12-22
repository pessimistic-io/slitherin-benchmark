// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface PolicyCenterEventError {
    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event CoverBought(
        address indexed buyer,
        uint256 indexed poolId,
        uint256 coverDuration,
        uint256 coverAmount,
        uint256 premiumInUSDC
    );

    event LiquidityProvided(address indexed user, uint256 amount);

    event LiquidityStaked(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );

    event LiquidityStakedWithoutFarming(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );

    event LiquidityUnstaked(
        address indexed user,
        uint256 indexed poolId,
        address priorityLP,
        uint256 amount
    );

    event LiquidityUnstakedWithoutFarming(
        address indexed user,
        uint256 indexed poolId,
        address priorityLP,
        uint256 amount
    );

    event LiquidityRemoved(address indexed user, uint256 amount);

    event PayoutClaimed(address indexed user, uint256 amount);

    event PremiumSplitted(
        uint256 toPriority,
        uint256 toProtection,
        uint256 toTreasury
    );

    event PremiumSwapped(address fromToken, uint256 amount, uint256 received);

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error PolicyCenter__AlreadyClaimedPayout(); // a2ded9c1
    error PolicyCenter__WrongPriorityPoolID(); // 67f304bf
    error PolicyCenter__InsufficientCapacity(); // 7730dc0b
    error PolicyCenter__OnlyPriorityPoolFactory(); // aca500b4
    error PolicyCenter__ZeroPremium(); // 720794bf
    error PolicyCenter__NoLiquidity(); // d5c16599
    error PolicyCenter__NoExchange(); // 7bb995d0
    error PolicyCenter__ZeroAmount(); // 1613633b
    error PolicyCenter__NoPayout(); // 6e472dea
    error PolicyCenter__NonExistentPool(); // 5824d49b
    error PolicyCenter__BadLength(); // 1eaaaf2c
    error PolicyCenter__PremiumTooHigh(); // 855e507b
    error PolicyCenter__InvalidPremiumSplit(); //
    error PolicyCenter__PoolPaused(); //
    error PolicyCenter__OnlyTreasury(); //
    error PolicyCenter__WrongPath();
}

