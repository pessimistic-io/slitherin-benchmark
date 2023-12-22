// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Errors.sol";
import "./ErrorCodes.sol";

contract EthLocker is Errors {
    // 0 means unlocked. 1 means locked
    uint8 private locked = 0;

    function lockEth() internal {
        locked = 1;
    }

    function unlockEth() internal {
        locked = 0;
    }

    modifier ethLocked() {
        _require(locked == 1, ErrorCodes.ETHER_AMOUNT_SURPASSES_MSG_VALUE);

        _;
    }

    modifier ethUnlocked() {
        _require(locked == 0, ErrorCodes.ETHER_AMOUNT_SURPASSES_MSG_VALUE);
        locked = 1;

        _;
    }
}

