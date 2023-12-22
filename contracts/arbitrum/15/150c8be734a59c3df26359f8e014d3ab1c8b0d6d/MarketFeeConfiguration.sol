/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import {UD60x18} from "./UD60x18.sol";
import "./Account.sol";

/**
 * @title Tracks market-level risk settings
 */
library MarketFeeConfiguration {
    using Account for Account.Data;

    struct Data {
        /**
         * @dev Id of the product for which we store fee configurations
         */
        uint128 productId;
        /**
         * @dev Id of the market for which we store fee configurations
         */
        uint128 marketId;
        /**
         * @dev Address of fee collector
         */
        uint128 feeCollectorAccountId;
        /**
         * @dev Atomic Maker Fee is multiplied by the annualised notional traded
         * @dev to derived the maker fee.
         */
        UD60x18 atomicMakerFee;
        /**
         * @dev Atomic Taker Fee is multiplied by the annualised notional traded
         * @dev to derived the taker fee.
         */
        UD60x18 atomicTakerFee;
    }

    /**
     * @dev Loads the MarketFeeConfiguration object for a given productId & marketId pair
     * @param productId Id of the product (e.g. IRS) for which we want to query the risk configuration
     * @param marketId Id of the market (e.g. aUSDC lend) for which we want to query the risk configuration
     * @return config The MarketFeeConfiguration object.
     */
    function load(uint128 productId, uint128 marketId) internal pure returns (Data storage config) {
        bytes32 s = keccak256(abi.encode("xyz.voltz.MarketFeeConfiguration", productId, marketId));
        assembly {
            config.slot := s
        }
    }

    /**
     * @dev Sets the fee configuration for a given productId & marketId pair
     * @param config The MarketFeeConfiguration object
     */
    function set(Data memory config) internal {
        Account.exists(config.feeCollectorAccountId);

        Data storage storedConfig = load(config.productId, config.marketId);

        storedConfig.productId = config.productId;
        storedConfig.marketId = config.marketId;
        storedConfig.feeCollectorAccountId = config.feeCollectorAccountId;
        storedConfig.atomicMakerFee = config.atomicMakerFee;
        storedConfig.atomicTakerFee = config.atomicTakerFee;
    }
}

