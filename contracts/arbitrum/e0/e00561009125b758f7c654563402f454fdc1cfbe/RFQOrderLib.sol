// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {SocketOrder, RFQOrder, BatchRFQOrder} from "./SocketStructs.sol";
import {SocketOrderLib} from "./SocketOrderLib.sol";

/// @notice helpers for handling RFQ Order objects
library RFQOrderLib {
    using SocketOrderLib for SocketOrder;

    // RFQ Order Type.
    bytes internal constant RFQ_ORDER_TYPE =
        abi.encodePacked(
            "RFQOrder(",
            "SocketOrder order,",
            "uint256 promisedAmount,",
            "bytes userSignature)"
        );

    // Main Order Type.
    bytes internal constant ORDER_TYPE =
        abi.encodePacked(RFQ_ORDER_TYPE, SocketOrderLib.SOCKET_ORDER_TYPE);

    // Keccak Hash of Main Order Type.
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    /// @notice hash a rfq order
    /// @param rfqOrder rfq order to be hashed
    function hash(RFQOrder memory rfqOrder) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ORDER_TYPE_HASH,
                    rfqOrder.order.hash(),
                    rfqOrder.promisedAmount,
                    keccak256(rfqOrder.userSignature)
                )
            );
    }

    /// @notice hash a batch of rfq orders
    /// @param batchOrder batch of rfq orders to be hashed
    function hashBatch(
        BatchRFQOrder memory batchOrder
    ) internal pure returns (bytes32) {
        unchecked {
            bytes32 outputHash = keccak256(
                "RFQOrder(SocketOrder order,uint256 promisedAmount,bytes userSignature)"
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

