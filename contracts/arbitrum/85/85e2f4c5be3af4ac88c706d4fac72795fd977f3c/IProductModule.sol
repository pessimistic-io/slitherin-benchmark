/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./Account.sol";

/**
 * @title System-wide entry point for the management of products connected to the protocol.
 */
interface IProductModule {
    /**
     * @notice Thrown when an attempt to register a product that does not conform to the IProduct interface is made.
     */
    error IncorrectProductInterface(address product);

    /**
     * @notice Emitted when a new product is registered in the protocol.
     * @param product The address of the product that was registered in the system.
     * @param productId The id with which the product was registered in the system.
     * @param sender The account that trigger the registration of the product and also the owner of the product.
     * @param blockTimestamp The current block timestamp.
     */
    event ProductRegistered(
        address indexed product, uint128 indexed productId, string name, address indexed sender, uint256 blockTimestamp
    );

    /**
     * @notice Emitted when account token with id `accountId` is closed.
     * @param accountId The id of the account.
     * @param collateralType The address of the collateral token.
     * @param sender The initiator of the account closure.
     * @param blockTimestamp The current block timestamp.
     */
    event AccountClosed(uint128 indexed accountId, address collateralType, address sender, uint256 blockTimestamp);

    /// @notice returns the unrealized pnl in quote token terms for account
    function getAccountUnrealizedPnL(uint128 productId, uint128 accountId, address collateralType)
        external
        returns (int256);

    /// @notice returns annualized filled notional, annualized unfilled notional long, annualized unfilled notional short
    function getAccountAnnualizedExposures(uint128 productId, uint128 accountId, address collateralType)
        external
        returns (Account.Exposure[] memory exposures);

    // state changing functions

    /**
     * @notice Connects a product to the system.
     * @dev Creates a product object to track the product, and returns the newly created product id.
     * @param product The address of the product that is to be registered in the system.
     * @return newProductId The id with which the product will be registered in the system.
     */
    function registerProduct(address product, string memory name) external returns (uint128 newProductId);

    /// @notice attempts to close all the unfilled and filled positions of a given account in a given product (productId)
    function closeAccount(uint128 productId, uint128 accountId, address collateralType) external;

    function propagateTakerOrder(
        uint128 accountId,
        uint128 productId,
        uint128 marketId,
        address collateralType,
        int256 annualizedNotional
    ) external returns (uint256 fee, uint256 im);

    function propagateMakerOrder(
        uint128 accountId,
        uint128 productId,
        uint128 marketId,
        address collateralType,
        int256 annualizedNotional
    ) external returns (uint256 fee, uint256 im);

    function propagateCashflow(uint128 accountId, uint128 productId, address collateralType, int256 amount) external;
}

