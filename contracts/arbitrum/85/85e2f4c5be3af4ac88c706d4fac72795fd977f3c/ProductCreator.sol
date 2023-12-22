/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./Product.sol";

/**
 * @title Encapsulates Product creation logic
 */
library ProductCreator {
    bytes32 private constant _SLOT_Product_CREATOR = keccak256(abi.encode("xyz.voltz.Products"));

    struct Data {
        /**
         * @dev Tracks an array of Product ids for each external IProduct address.
         */
        mapping(address => uint128[]) productIdsForAddress;
        /**
         * @dev Keeps track of the last Product id created.
         * Used for easily creating new Products.
         */
        uint128 lastCreatedProductId;
    }

    /**
     * @dev Returns the singleton Product store of the system.
     */
    function getProductStore() internal pure returns (Data storage productStore) {
        bytes32 s = _SLOT_Product_CREATOR;
        assembly {
            productStore.slot := s
        }
    }

    /**
     * @dev Given an external contract address representing an `IProduct`, creates a new id for the Product, and tracks it
     * internally in the protocol.
     *
     * The id used to track the Product will be automatically assigned by the protocol according to the last id used.
     *
     * Note: If an external `IProduct` contract tracks several Product ids, this function should be called for each Product it
     * tracks, resulting in multiple ids for the same address.
     * For example if a given Product works across maturities, each maturity internally will be represented as a unique Product id
     */
    function create(address productAddress, string memory name, address owner)
        internal
        returns (Product.Data storage product)
    {
        Data storage productStore = getProductStore();

        uint128 id = productStore.lastCreatedProductId + 1;
        product = Product.load(id);

        product.id = id;
        product.productAddress = productAddress;
        product.name = name;
        product.owner = owner;
        productStore.lastCreatedProductId = id;

        loadIdsByAddress(productAddress).push(id);
    }

    /**
     * @dev Returns an array of Product ids representing the Products linked to the system at a particular external contract
     * address.
     *
     * Note: A contract implementing the `IProduct` interface may represent more than just one Product, and thus several Product ids
     * could be associated to a single external contract address.
     */
    function loadIdsByAddress(address productAddress) internal view returns (uint128[] storage ids) {
        return getProductStore().productIdsForAddress[productAddress];
    }
}

