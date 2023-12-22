// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {BasicInfo, SocketOrder} from "./SocketStructs.sol";
import {BasicInfoLib} from "./BasicInfoLib.sol";
import {Permit2Lib} from "./Permit2Lib.sol";

/// @notice helpers for handling OrderInfo objects
library SocketOrderLib {
    // All hashes and encoding done to match EIP 712.

    using BasicInfoLib for BasicInfo;

    // Socket Order Type.
    bytes internal constant SOCKET_ORDER_TYPE =
        abi.encodePacked(
            "SocketOrder(",
            "BasicInfo info,",
            "address receiver,",
            "address outputToken,",
            "uint256 minOutputAmount,",
            "uint256 fromChainId,",
            "uint256 toChainId)"
        );

    // Main Order Type.
    bytes internal constant ORDER_TYPE =
        abi.encodePacked(SOCKET_ORDER_TYPE, BasicInfoLib.BASIC_INFO_TYPE);

    // Keccak Hash of Main Order Type.
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    // Permit 2 Witness Order Type.
    string internal constant PERMIT2_ORDER_TYPE =
        string(
            abi.encodePacked(
                "SocketOrder witness)",
                abi.encodePacked(
                    BasicInfoLib.BASIC_INFO_TYPE,
                    SOCKET_ORDER_TYPE
                ),
                Permit2Lib.TOKEN_PERMISSIONS_TYPE
            )
        );

    /// @notice hash Socket Order.
    /// @param order Socket Order
    function hash(SocketOrder memory order) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ORDER_TYPE_HASH,
                    order.info.hash(),
                    order.receiver,
                    order.outputToken,
                    order.minOutputAmount,
                    order.fromChainId,
                    order.toChainId
                )
            );
    }
}

