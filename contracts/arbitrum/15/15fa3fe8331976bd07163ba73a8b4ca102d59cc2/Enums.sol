// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

library Enums {
    enum BuyFrequency {
        DAILY,
        WEEKLY,
        BI_WEEKLY,
        MONTHLY
    }

    enum AssetTypes {
        STABLE,
        ETH_BTC,
        BLUE_CHIP
    }

    enum StrategyTimeLimitsInDays {
        THIRTY,
        NINETY,
        ONE_HUNDRED_AND_EIGHTY,
        THREE_HUNDRED_AND_SIXTY_FIVE
    }
}

