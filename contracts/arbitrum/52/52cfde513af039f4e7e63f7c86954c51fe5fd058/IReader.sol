// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./IDataStore.sol";
import "./IMarket.sol";
import "./IPrice.sol";
import "./IMarketPoolValueInfo.sol";

interface IReader {
    function getMarketTokenPrice(
        IDataStore dataStore,
        IMarket.Props memory market,
        IPrice.Props memory indexTokenPrice,
        IPrice.Props memory longTokenPrice,
        IPrice.Props memory shortTokenPrice,
        bytes32 pnlFactorType,
        bool maximize
    ) external view returns (int256, IMarketPoolValueInfo.Props memory);
}
