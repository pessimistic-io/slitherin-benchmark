// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./StructData.sol";

interface IExchangeRouter {
  function sendWnt(address receiver, uint256 amount) external payable;
  function sendTokens(address token, address receiver, uint256 amount) external payable;
  function createOrder(
    CreateOrderParams calldata params
  ) external payable returns (bytes32);
  function cancelOrder(bytes32 key) external payable;
}

