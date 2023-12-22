// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IRegistry.sol";
import "./IBook.sol";

interface IMarketBook is IBook {
  event OpenPendingMarketOrderEvent(
    address indexed sender,
    bytes32 indexed orderHash,
    OpenTradeInput openData
  );
  event ExecutePendingMarketOrderEvent(bytes32 indexed orderHash);
  event FailedExecutePendingMarketOrderEvent(
    bytes32 indexed orderHash,
    string returnData
  );

  function openPendingMarketOrder(OpenTradeInput calldata openData) external;

  function executePendingMarketOrder(
    bytes32 orderHash,
    bytes[] calldata priceData
  ) external payable;
}

