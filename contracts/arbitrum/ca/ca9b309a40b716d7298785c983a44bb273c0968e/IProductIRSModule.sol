/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

import "./IProduct.sol";
import "./ProductConfiguration.sol";

/// @title Interface of a dated irs product
interface IProductIRSModule is IProduct {
    event ProductConfigured(ProductConfiguration.Data config, uint256 blockTimestamp);

    /**
     * @notice Emitted when a taker order of the account token with id `accountId` is initiated.
     * @param accountId The id of the account.
     * @param productId The id of the product.
     * @param marketId The id of the market.
     * @param maturityTimestamp The maturity timestamp of the position.
     * @param collateralType The address of the collateral.
     * @param executedBaseAmount The executed base amount of the order.
     * @param executedQuoteAmount The executed quote amount of the order.
     * @param annualizedNotionalAmount The annualized base of the order.
     * @param blockTimestamp The current block timestamp.
     */
    event TakerOrder(
        uint128 indexed accountId,
        uint128 productId,
        uint128 indexed marketId,
        uint32 indexed maturityTimestamp,
        address collateralType,
        int256 executedBaseAmount,
        int256 executedQuoteAmount,
        int256 annualizedNotionalAmount,
        uint256 blockTimestamp
    );

    /**
     * @notice Emitted when a position is settled.
     * @param accountId The id of the account.
     * @param productId The id of the product.
     * @param marketId The id of the market.
     * @param maturityTimestamp The maturity timestamp of the position.
     * @param collateralType The address of the collateral.
     * @param blockTimestamp The current block timestamp.
     */
    event DatedIRSPositionSettled(
        uint128 indexed accountId,
        uint128 productId,
        uint128 indexed marketId,
        uint32 indexed maturityTimestamp,
        address collateralType,
        int256 settlementCashflowInQuote,
        uint256 blockTimestamp
    );

    /**
     * @notice Thrown when an attempt to access a function without authorization.
     */
    error NotAuthorized(address caller, bytes32 functionName);

    // process taker and maker orders & single pool

    /**
     * @notice Returns the address that owns a given account, as recorded by the protocol.
     * @param accountId Id of the account that wants to settle
     * @param marketId Id of the market in which the account wants to settle (e.g. 1 for aUSDC lend)
     * @param maturityTimestamp Maturity timestamp of the market in which the account wants to settle
     */
    function settle(uint128 accountId, uint128 marketId, uint32 maturityTimestamp) external;

    /**
     * @notice Initiates a taker order for a given account by consuming liquidity provided by the pool connected to this product
     * @dev Initially a single pool is connected to a single product, however, that doesn't need to be the case in the future
     * @param accountId Id of the account that wants to initiate a taker order
     * @param marketId Id of the market in which the account wants to initiate a taker order (e.g. 1 for aUSDC lend)
     * @param maturityTimestamp Maturity timestamp of the market in which the account wants to initiate a taker order
     * @param priceLimit The Q64.96 sqrt price limit. If !isFT, the price cannot be less than this
     * @param baseAmount Amount of notional that the account wants to trade in either long (+) or short (-) direction depending on
     * sign
     */
    function initiateTakerOrder(
        uint128 accountId,
        uint128 marketId,
        uint32 maturityTimestamp,
        int256 baseAmount,
        uint160 priceLimit
    )
        external
        returns (int256 executedBaseAmount, int256 executedQuoteAmount, uint256 fee, uint256 im);

    /**
     * @notice Creates or updates the configuration for the given product.
     * @param config The ProductConfiguration object describing the new configuration.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner of the system.
     *
     * Emits a {ProductConfigured} event.
     *
     */
    function configureProduct(ProductConfiguration.Data memory config) external;

    /**
     * @notice Propagates maker order to core to check margin requirements
     * @param accountId Id of the account that wants to initiate a taker order
     * @param marketId Id of the market in which the account wants to initiate a taker order (e.g. 1 for aUSDC lend)
     * @param annualizedBaseAmount The annualized notional of the order
     */
    function propagateMakerOrder(
        uint128 accountId,
        uint128 marketId,
        int256 annualizedBaseAmount
    ) external returns (uint256 fee, uint256 im);

    /**
     * @notice Returns core proxy address from ProductConfigruation
     */
    function getCoreProxyAddress() external returns (address);
}

