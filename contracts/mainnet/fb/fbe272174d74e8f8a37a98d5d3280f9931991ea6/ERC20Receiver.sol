// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {IERC20Receiver} from "./IERC20Receiver.sol";
import {InterfaceDetectionStorage} from "./InterfaceDetectionStorage.sol";
import {InterfaceDetection} from "./InterfaceDetection.sol";

/// @title ERC20 Fungible Token Standard, Receiver (immutable version).
/// @dev This contract is to be used via inheritance in an immutable (non-proxied) implementation.
abstract contract ERC20Receiver is IERC20Receiver, InterfaceDetection {
    using InterfaceDetectionStorage for InterfaceDetectionStorage.Layout;

    /// @notice Marks the following ERC165 interface(s) as supported: ERC20Receiver.
    constructor() {
        InterfaceDetectionStorage.layout().setSupportedInterface(type(IERC20Receiver).interfaceId, true);
    }
}

