// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./IDataStore.sol";
import "./StructData.sol";
import "./Position.sol";
import "./Order.sol";

interface IReader {
  function getMarket(address dataStore, address key) external view returns (MarketProps memory);
  // function getMarkets(IDataStore dataStore, uint256 start, uint256 end) external view returns (MarketProps[] memory);
  function getPosition(address dataStore, bytes32 key) external view returns (Position.Props memory);
  function getAccountOrders(
    address dataStore,
    address account,
    uint256 start,
    uint256 end
  ) external view returns (Order.Props[] memory);
  function getPositionInfo(
    address dataStore,
    address referralStorage,
    bytes32 positionKey,
    MarketPrices memory prices,
    uint256 sizeDeltaUsd,
    address uiFeeReceiver,
    bool usePositionSizeAsSizeDeltaUsd
  ) external view returns (PositionInfo memory);
}

