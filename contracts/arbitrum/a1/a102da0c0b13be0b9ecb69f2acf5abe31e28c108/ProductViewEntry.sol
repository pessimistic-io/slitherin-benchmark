// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { IProductViewEntry } from "./IProductViewEntry.sol";
import { CegaStorage, CegaGlobalStorage } from "./CegaStorage.sol";

contract ProductViewEntry is IProductViewEntry, CegaStorage {
    function getStrategyOfProduct(
        uint32 productId
    ) external view returns (uint32) {
        CegaGlobalStorage storage cgs = getStorage();
        return cgs.strategyOfProduct[productId];
    }
}

