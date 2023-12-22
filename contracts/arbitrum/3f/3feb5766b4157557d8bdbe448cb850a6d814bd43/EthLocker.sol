// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Errors.sol";
import "./ErrorCodes.sol";

/// @title Handles ETH re-usabilitiy
/// @author Pino Development Team
contract EthLocker is Errors {
    // 2 means unlocked. 1 means locked
    // If locked is equal to 1, then function with the ethUnlocked modifier revert
    // If locked is equal to 2, then only 1 function with the ethUnlocked modifier works
    uint8 private locked = 2;

    /// @notice Locks functions that work with ETH directly
    function lockEth() internal {
        locked = 1;
    }

    /// @notice Unlocks functions that work with ETH directly
    function unlockEth() internal {
        locked = 2;
    }

    /// @notice Checks whether eth has been used in another function or not
    modifier ethLocked() {
        _require(locked == 1, ErrorCodes.ETHER_AMOUNT_SURPASSES_MSG_VALUE);

        _;
    }

    /// @notice Checks whether
    modifier ethUnlocked() {
        _require(locked == 2, ErrorCodes.ETHER_AMOUNT_SURPASSES_MSG_VALUE);
        locked = 1;

        _;
    }
}

