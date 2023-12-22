// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { ProductMetadata } from "./Structs.sol";
import { IProductViewEntry } from "./IProductViewEntry.sol";
import { CegaStorage, CegaGlobalStorage } from "./CegaStorage.sol";

contract ProductViewEntry is IProductViewEntry, CegaStorage {
    function getStrategyOfProduct(
        uint32 productId
    ) external view returns (uint32) {
        CegaGlobalStorage storage cgs = getStorage();
        return cgs.strategyOfProduct[productId];
    }

    function getLatestProductId() external view returns (uint32) {
        CegaGlobalStorage storage cgs = getStorage();
        return cgs.productIdCounter;
    }

    function getProductMetadata(
        uint32 productId
    ) external view returns (ProductMetadata memory) {
        CegaGlobalStorage storage cgs = getStorage();
        return cgs.productMetadata[productId];
    }
}

