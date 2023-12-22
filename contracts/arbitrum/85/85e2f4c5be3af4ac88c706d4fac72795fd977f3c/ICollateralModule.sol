/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

/**
 * @title Module for managing user collateral.
 * @notice Allows users to deposit and withdraw collateral from the protocol
 */
interface ICollateralModule {
    /**
     * @notice Thrown on deposit when the collateral cap would have been exceeded
     * @param collateralType The address of the collateral of the unsuccessful deposit
     * @param collateralCap The cap limit of the collateral
     * @param currentBalance Protocol's total balance in the collateral type
     * @param tokenAmount The token amount of the unsuccessful deposit
     * @param liquidationBoosterDeposit The amount paid towards the liquidation booster
     * (up to ConfigurationConfiguration.liquidationBooster)
     */
    error CollateralCapExceeded(
        address collateralType,
        uint256 collateralCap,
        uint256 currentBalance,
        uint256 tokenAmount,
        uint256 liquidationBoosterDeposit
    );

    /**
     * @notice Emitted when `tokenAmount` of collateral of type `collateralType` is deposited to account `accountId` by `sender`.
     * @param accountId The id of the account that deposited collateral.
     * @param collateralType The address of the collateral that was deposited.
     * @param tokenAmount The amount of collateral that was deposited, denominated in the token's native decimal representation.
     * @param sender The address of the account that triggered the deposit.
     * @param blockTimestamp The current block timestamp.
     */
    event Deposited(
        uint128 indexed accountId,
        address indexed collateralType,
        uint256 tokenAmount,
        address indexed sender,
        uint256 blockTimestamp
    );

    /**
     * @notice Emitted when `tokenAmount` of collateral of type `collateralType` is withdrawn from account `accountId` by `sender`.
     * @param accountId The id of the account that withdrew collateral.
     * @param collateralType The address of the collateral that was withdrawn.
     * @param tokenAmount The amount of collateral that was withdrawn, denominated in the token's native decimal representation.
     * @param sender The address of the account that triggered the withdrawal.
     * @param blockTimestamp The current block timestamp.
     */
    event Withdrawn(
        uint128 indexed accountId, 
        address indexed collateralType, 
        uint256 tokenAmount, 
        address indexed sender, 
        uint256 blockTimestamp
    );

    /**
     * @notice Returns the total balance pertaining to account `accountId` for `collateralType`.
     * @param accountId The id of the account whose collateral is being queried.
     * @param collateralType The address of the collateral type whose amount is being queried.
     * @return collateralBalance The total collateral deposited in the account, denominated in
     * the token's native decimal representation.
     */
    function getAccountCollateralBalance(uint128 accountId, address collateralType)
        external
        view
        returns (uint256 collateralBalance);

    /**
     * @notice Returns the amount of collateral of type `collateralType` deposited with account `accountId` that can be withdrawn
     * @param accountId The id of the account whose collateral is being queried.
     * @param collateralType The address of the collateral type whose amount is being queried.
     * @return amount The amount of collateral that is available for withdrawal (difference between balance and IM), denominated
     * in the token's native decimal representation.
     */
    function getAccountCollateralBalanceAvailable(uint128 accountId, address collateralType)
        external
        returns (uint256 amount);

    /**
     * @notice Returns the total liquidation booster pertaining to account `accountId` for `collateralType`.
     * @param accountId The id of the account whose collateral is being queried.
     * @param collateralType The address of the collateral type whose amount is being queried.
     * @return liquidationBoosterBalance The total liquidation booster deposited in the account, denominated
     * in the token's native decimal representation.
     */
    function getAccountLiquidationBoosterBalance(uint128 accountId, address collateralType)
        external
        view
        returns (uint256 liquidationBoosterBalance);

    /**
     * @notice Returns the total account value pertaining to account `accountId` in terms of the quote token of the (single token)
     * account
     * @param accountId The id of the account whose total account value is being queried.
     * @return totalAccountValue The total account value in terms of the quote token of the account, denominated in
     * the token's native decimal representation.
     */
    function getTotalAccountValue(uint128 accountId, address collateralType)
        external
        view
        returns (int256 totalAccountValue);

    /**
     * @notice Deposits `tokenAmount` of collateral of type `collateralType` into account `accountId`.
     * @dev Anyone can deposit into anyone's active account without restriction.
     * @param accountId The id of the account that is making the deposit.
     * @param collateralType The address of the token to be deposited.
     * @param tokenAmount The amount being deposited, denominated in the token's native decimal representation.
     *
     * Emits a {Deposited} event.
     */
    function deposit(uint128 accountId, address collateralType, uint256 tokenAmount) external;

    /**
     * @notice Withdraws `tokenAmount` of collateral of type `collateralType` from account `accountId`.
     * @param accountId The id of the account that is making the withdrawal.
     * @param collateralType The address of the token to be withdrawn.
     * @param tokenAmount The amount being withdrawn, denominated in the token's native decimal representation.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner of the account
     *
     * Emits a {Withdrawn} event.
     *
     */
    function withdraw(uint128 accountId, address collateralType, uint256 tokenAmount) external;
}

