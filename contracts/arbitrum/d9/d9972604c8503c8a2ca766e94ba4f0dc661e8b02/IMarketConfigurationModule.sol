/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

import "./MarketConfiguration.sol";

/**
 * @title Module for configuring a market
 * @notice Allows the owner to configure the quote token of the given market
 */

interface IMarketConfigurationModule {
    /**
     * @notice Emitted when a market configuration is created or updated
     * @param config The object with the newly configured details.
     * @param blockTimestamp The current block timestamp.
     */
    event MarketConfigured(MarketConfiguration.Data config, uint256 blockTimestamp);

    /**
     * @notice Creates or updates the market configuration
     * @param config The MarketConfiguration object describing the new configuration.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner of the dated irs product.
     *
     * Emits a {MarketConfigured} event.
     *
     */
    function configureMarket(MarketConfiguration.Data memory config) external;

    /**
     * @notice Returns the market configuration
     * @return config The configuration object describing the market
     */
    function getMarketConfiguration(uint128 irsMarketId) external view returns (MarketConfiguration.Data memory config);
}

