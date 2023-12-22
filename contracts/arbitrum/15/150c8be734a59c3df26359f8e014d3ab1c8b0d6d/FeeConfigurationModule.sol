/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./OwnableStorage.sol";
import "./IFeeConfigurationModule.sol";
import "./MarketFeeConfiguration.sol";

contract FeeConfigurationModule is IFeeConfigurationModule {
    /**
     * @inheritdoc IFeeConfigurationModule
     */
    function configureMarketFee(MarketFeeConfiguration.Data memory config) external override {
        OwnableStorage.onlyOwner();
        MarketFeeConfiguration.set(config);
        emit MarketFeeConfigured(config, block.timestamp);
    }

    /**
     * @inheritdoc IFeeConfigurationModule
     */
    function getMarketFeeConfiguration(uint128 productId, uint128 marketId)
        external
        pure
        override
        returns (MarketFeeConfiguration.Data memory config)
    {
        return MarketFeeConfiguration.load(productId, marketId);
    }
}

