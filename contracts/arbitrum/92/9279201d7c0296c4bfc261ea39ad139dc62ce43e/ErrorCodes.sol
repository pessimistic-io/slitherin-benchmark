// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

library ErrorCodes {
    uint256 internal constant FAILED_TO_SEND_ETHER = 0;
    uint256 internal constant ETHER_AMOUNT_SURPASSES_MSG_VALUE = 1;

    uint256 internal constant TOKENS_MISMATCHED = 2;
}

