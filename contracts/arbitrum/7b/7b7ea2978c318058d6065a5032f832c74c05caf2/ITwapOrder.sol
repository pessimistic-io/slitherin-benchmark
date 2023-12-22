// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

interface ITwapOrder {
    function updatePriceLimit(uint256) external;
    function openOrder(uint256, uint256, uint256, uint256) external;
    function deposit(uint256) external;
    function swap(uint256, uint256, bytes memory) external;
    function cancelOrder() external;
    function closeOrder() external;
    function getOrderMetrics() external view returns (
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        address,
        address,
        uint8,
        bool
    );
}
