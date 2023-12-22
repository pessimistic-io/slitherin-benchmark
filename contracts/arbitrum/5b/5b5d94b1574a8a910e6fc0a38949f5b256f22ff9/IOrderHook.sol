// SPDX-License-Identifier: UNLICENSED

pragma solidity >= 0.8.0;

interface IOrderHook {
    function postPlaceOrder(uint256 orderId, bytes calldata extradata) external;

    function preSwap(address sender, bytes calldata extradata) external;

    function postPlaceSwapOrder(uint256 swapOrderId, bytes calldata extradata) external;
}

