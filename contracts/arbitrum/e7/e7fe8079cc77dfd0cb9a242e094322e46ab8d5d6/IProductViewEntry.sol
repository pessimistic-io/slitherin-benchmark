// SPDX-License-Identifier: BUSL-1.1

import { ProductMetadata } from "./Structs.sol";

pragma solidity ^0.8.17;

interface IProductViewEntry {
    function getStrategyOfProduct(
        uint32 productId
    ) external view returns (uint32);

    function getLatestProductId() external view returns (uint32);

    function getProductMetadata(
        uint32 productId
    ) external view returns (ProductMetadata memory);
}

