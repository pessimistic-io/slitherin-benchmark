// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.6;

import "./Router.sol";

interface IHandler {
  function onOrderCreated(SmartTradeRouter.Order calldata order) external;

  function handle(SmartTradeRouter.Order calldata order, bytes calldata options) external;
}

