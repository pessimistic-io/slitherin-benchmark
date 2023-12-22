/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

/**
 * @title Stores information about a deposited asset for a given account.
 *
 * Each account will have one of these objects for each type of collateral it deposited in the system.
 */
library Collateral {
    /**
     * @dev Thrown when an account does not have sufficient collateral.
     */
    error InsufficientCollateral(uint256 requestedAmount);

    /**
     * @dev Thrown when an account does not have sufficient collateral.
     */
    error InsufficientLiquidationBoosterBalance(uint256 requestedAmount);

    /**
     * @notice Emitted when collateral balance of account token with id `accountId` is updated.
     * @param accountId The id of the account.
     * @param collateralType The address of the collateral type.
     * @param tokenAmount The change delta of the collateral balance.
     * @param blockTimestamp The current block timestamp.
     */
    event CollateralUpdate(uint128 indexed accountId, address indexed collateralType, int256 tokenAmount, uint256 blockTimestamp);

    /**
     * @notice Emitted when liquidator booster deposit of `accountId` is updated.
     * @param accountId The id of the account.
     * @param collateralType The address of the collateral type.
     * @param tokenAmount The change delta of the collateral balance.
     * @param blockTimestamp The current block timestamp.
     */
    event LiquidatorBoosterUpdate(
        uint128 indexed accountId, 
        address indexed collateralType, 
        int256 tokenAmount, 
        uint256 blockTimestamp
    );

    struct Data {
        /**
         * @dev The net amount that is deposited in this collateral
         */
        uint256 balance;
        /**
         * @dev The amount of tokens the account has in liquidation booster. Max value is
         * @dev liquidation booster defined in CollateralConfiguration.
         */
        uint256 liquidationBoosterBalance;
    }

    /**
     * @dev Increments the entry's balance.
     */
    function increaseCollateralBalance(Data storage self, uint256 amount) internal {
        self.balance += amount;
    }

    /**
     * @dev Decrements the entry's balance.
     */
    function decreaseCollateralBalance(Data storage self, uint256 amount) internal {
        if (self.balance < amount) {
            revert InsufficientCollateral(amount);
        }

        self.balance -= amount;
    }

    /**
     * @dev Increments the entry's liquidation booster balance.
     */
    function increaseLiquidationBoosterBalance(Data storage self, uint256 amount) internal {
        self.liquidationBoosterBalance += amount;
    }

    /**
     * @dev Decrements the entry's liquidation booster balance.
     */
    function decreaseLiquidationBoosterBalance(Data storage self, uint256 amount) internal {
        if (self.liquidationBoosterBalance < amount) {
            revert InsufficientLiquidationBoosterBalance(amount);
        }

        self.liquidationBoosterBalance -= amount;
    }
}

