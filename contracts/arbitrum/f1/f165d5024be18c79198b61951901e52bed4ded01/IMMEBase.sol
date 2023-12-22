// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {DataTypes} from "./DataTypes.sol";

/**
 * @title IMMEBase
 * @author Souq.Finance
 * @notice Defines the interface of the MME Base.
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */
interface IMMEBase {
    /**
     * @dev Emitted when the pool fee changes
     * @param _newFee The new fee
     */
    event FeeChanged(DataTypes.PoolFee _newFee);


    /**
     * @dev Emitted when the Pool Iterative limits are changed
     * @param _limits The new pool data limit
     */
    event PoolIterativeLimitsSet(DataTypes.IterativeLimit _limits);

    /**
     * @dev Emitted when the Pool Liquidity limits are changed
     * @param _limits The new pool data limit
     */
    event PoolLiquidityLimitsSet(DataTypes.LiquidityLimit _limits);

    /**
     * @dev Function to set the pool fee
     * @param _newFee The new fee struct
     */
    function setFee(DataTypes.PoolFee calldata _newFee) external;

    /**
     * @dev Function to set the Pool Iterative limits for the bonding curve
     * @param _newLimits The new limits struct
     */
    function setPoolIterativeLimits(DataTypes.IterativeLimit calldata _newLimits) external;

    /**
     * @dev Function to set the Pool liquidity limits for deposits and withdrawals of liquidity
     * @param _newLimits The new limits struct
     */
    function setPoolLiquidityLimits(DataTypes.LiquidityLimit calldata _newLimits) external;
}
