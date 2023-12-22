/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

import "./IMarketConfigurationModule.sol";
import "./MarketConfiguration.sol";
import "./OwnableStorage.sol";

/**
 * @title Module for configuring a market
 * @dev See IMarketConfigurationModule.
 */
contract MarketConfigurationModule is IMarketConfigurationModule {
    using MarketConfiguration for MarketConfiguration.Data;

    /**
     * @inheritdoc IMarketConfigurationModule
     */
    function configureMarket(MarketConfiguration.Data memory config) external {
        OwnableStorage.onlyOwner();

        MarketConfiguration.set(config);

        emit MarketConfigured(config, block.timestamp);
    }

    /**
     * @inheritdoc IMarketConfigurationModule
     */
    function getMarketConfiguration(uint128 irsMarketId) external pure returns (MarketConfiguration.Data memory config) {
        return MarketConfiguration.load(irsMarketId);
    }
}

