// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {BasicInfo} from "./SocketStructs.sol";

/// @notice helpers for handling OrderInfo objects
library BasicInfoLib {
    bytes internal constant BASIC_INFO_TYPE =
        "BasicInfo(address sender,address inputToken,uint256 inputAmount,uint256 nonce,uint256 deadline)";
    bytes32 internal constant ORDER_INFO_TYPE_HASH = keccak256(BASIC_INFO_TYPE);

    /// @notice hash an OrderInfo object
    /// @param info The OrderInfo object to hash
    function hash(BasicInfo memory info) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ORDER_INFO_TYPE_HASH,
                    info.sender,
                    info.inputToken,
                    info.inputAmount,
                    info.nonce,
                    info.deadline
                )
            );
    }
}

