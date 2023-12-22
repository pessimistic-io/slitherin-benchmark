/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

/**
 * @title Tracks configurations for the Products
 * note Enables the owner of the ProductProxy to configure the pool address the product is linked to
 */
library ProductConfiguration {
    bytes32 private constant _SLOT_PRODUCT_CONFIGURATION = keccak256(abi.encode("xyz.voltz.ProductConfiguration"));

    struct Data {
        /**
         * @dev Id for a given interest rate swap market
         */
        uint128 productId;
        /**
         * @dev Address of the core proxy
         */
        address coreProxy;
        /**
         * @dev Address of the pool address the product is linked to
         */
        address poolAddress;
    }

    /**
     * @dev Loads the ProductConfiguration object
     * @return productConfig The ProductConfiguration object.
     */
    function load() internal pure returns (Data storage productConfig) {
        bytes32 s = _SLOT_PRODUCT_CONFIGURATION;
        assembly {
            productConfig.slot := s
        }
    }

    /**
     * @dev Configures a product
     * @param config The ProductConfiguration object with all the settings for the product being configured.
     */
    function set(Data memory config) internal {
        Data storage storedConfig = load();

        //todo: check interface id of pool address

        storedConfig.productId = config.productId;
        storedConfig.coreProxy = config.coreProxy;
        storedConfig.poolAddress = config.poolAddress;
    }

    function getPoolAddress() internal view returns (address storedPoolAddress) {
        Data storage storedConfig = load();
        storedPoolAddress = storedConfig.poolAddress;
    }

    function getCoreProxyAddress() internal view returns (address storedProxyAddress) {
        Data storage storedConfig = load();
        storedProxyAddress = storedConfig.coreProxy;
    }

    function getProductId() internal view returns (uint128 storedProductId) {
        Data storage storedConfig = load();
        storedProductId = storedConfig.productId;
    }
}

