// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

library SafeTransferEth {
    function transferEth(address recipient, uint amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "eth transfer failure");
    }
}
