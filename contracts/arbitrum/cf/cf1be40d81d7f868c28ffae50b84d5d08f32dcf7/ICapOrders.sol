// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICapOrders {
    struct Order {
        uint256 orderId; // incremental order id
        address user; // user that submitted the order
        address asset; // Asset address, e.g. address(0) for ETH
        string market; // Market this order was submitted on
        uint256 margin; // Collateral tied to this order. In wei
        uint256 size; // Order size (margin * leverage). In wei
        uint256 price; // The order's price if its a trigger or protected order
        uint256 fee; // Fee amount paid. In wei
        bool isLong; // Wether the order is a buy or sell order
        uint8 orderType; // 0 = market, 1 = limit, 2 = stop
        bool isReduceOnly; // Wether the order is reduce-only
        uint256 timestamp; // block.timestamp at which the order was submitted
        uint256 expiry; // block.timestamp at which the order expires
        uint256 cancelOrderId; // orderId to cancel when this order executes
    }

    function submitOrder(Order memory params, uint256 tpPrice, uint256 slPrice) external payable;
    function cancelOrder(uint256 orderId) external;
    function cancelOrders(uint256[] calldata orderIds) external;
}

