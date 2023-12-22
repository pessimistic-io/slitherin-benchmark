/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./MarketFeeConfiguration.sol";

/**
 * @title Module for configuring (protocol and) market wide risk parameters
 * @notice Allows the owner to configure risk parameters at (protocol and) market wide level
 */
interface IFeeConfigurationModule {
    /**
     * @notice Emitted when a market fee configuration is created or updated
     * @param config The object with the newly configured details.
     * @param blockTimestamp The current block timestamp.
     */
    event MarketFeeConfigured(MarketFeeConfiguration.Data config, uint256 blockTimestamp);

    /**
     * @notice Creates or updates the fee configuration for the given `productId` and `marketId` pair
     * @param config The MarketFeeConfiguration object describing the new configuration.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner of the protocol.
     *
     * Emits a {MarketFeeConfigured} event.
     *
     */
    function configureMarketFee(MarketFeeConfiguration.Data memory config) external;

    /**
     * @notice Returns detailed information pertaining the specified productId and marketId pair
     * @param productId Id that uniquely identifies the product (e.g. Dated IRS) for which we want to query the risk config
     * @param marketId Id that uniquely identifies the market (e.g. aUSDC lend) for which we want to query the risk config
     * @return config The fee configuration object describing the given productId and marketId pair
     */
    function getMarketFeeConfiguration(uint128 productId, uint128 marketId)
        external
        pure
        returns (MarketFeeConfiguration.Data memory config);
}

