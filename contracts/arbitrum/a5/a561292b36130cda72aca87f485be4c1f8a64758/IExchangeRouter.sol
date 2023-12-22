// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./BaseOrderUtils.sol";

interface IExchangeRouter {
    function createOrder(BaseOrderUtils.CreateOrderParams calldata params) external payable returns (bytes32);
    function cancelOrder(bytes32 key) external payable;
}

