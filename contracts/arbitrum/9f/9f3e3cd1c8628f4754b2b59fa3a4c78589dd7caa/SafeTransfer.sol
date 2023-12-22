// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IWETH9.sol";

library SafeTransfer {
    // must use nonReentrant modifier
    function unwrapWETH9(
        address WETH,
        address recipient,
        uint256 amount
    ) internal returns (bool success) {
        uint256 balanceWETH9 = IWETH9(WETH).balanceOf(address(this));
        if (amount > balanceWETH9) {
            return false;
        }
        IWETH9(WETH).withdraw(amount);
        success = safeTransferETH(recipient, amount);
    }

    // must use nonReentrant modifier
    function safeTransferETH(
        address recipient,
        uint256 value
    ) internal returns (bool success) {
        (success, ) = recipient.call{value: value}(new bytes(0));
    }
}

