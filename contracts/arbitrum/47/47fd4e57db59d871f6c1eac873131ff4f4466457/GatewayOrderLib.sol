// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {SocketOrder, GatewayOrder, BatchGatewayOrder} from "./SocketStructs.sol";
import {SocketOrderLib} from "./SocketOrderLib.sol";

/// @notice helpers for handling Gateway Order objects
library GatewayOrderLib {
    using SocketOrderLib for SocketOrder;

    // Gateway Order Type.
    bytes internal constant GATEWAY_ORDER_TYPE =
        abi.encodePacked(
            "GatewayOrder(",
            "SocketOrder order,",
            "uint256 gatewayValue,",
            "bytes gatewayPayload,",
            "bytes userSignature)"
        );

    // Main Order Type.
    bytes internal constant ORDER_TYPE =
        abi.encodePacked(GATEWAY_ORDER_TYPE, SocketOrderLib.SOCKET_ORDER_TYPE);

    // Keccak Hash of Main Order Type.
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    /// @notice hash a gateway order
    /// @param gatewayOrder gateway order to be hashed
    function hash(
        GatewayOrder memory gatewayOrder
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ORDER_TYPE_HASH,
                    gatewayOrder.order.hash(),
                    gatewayOrder.gatewayValue,
                    keccak256(gatewayOrder.gatewayPayload),
                    keccak256(gatewayOrder.userSignature)
                )
            );
    }

    /// @notice hash a batch of gateway orders
    /// @param batchOrder batch of gateway orders to be hashed
    function hashBatch(
        BatchGatewayOrder memory batchOrder
    ) internal pure returns (bytes32) {
        unchecked {
            bytes32 outputHash = keccak256(
                "GatewayOrder(SocketOrder order,uint256 gatewayValue,bytes gatewayPayload,bytes userSignature)"
            );
            for (uint256 i = 0; i < batchOrder.orders.length; i++) {
                outputHash = keccak256(
                    abi.encode(outputHash, hash(batchOrder.orders[i]))
                );
            }
            return outputHash;
        }
    }
}

