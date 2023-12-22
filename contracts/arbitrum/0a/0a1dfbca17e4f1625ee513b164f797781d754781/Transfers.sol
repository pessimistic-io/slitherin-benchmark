// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {     IERC20,     SafeERC20 } from "./SafeERC20.sol";

library Transfers {
    using SafeERC20 for IERC20;

    function receiveTo(
        address asset,
        address to,
        uint256 amount
    ) internal returns (uint256 nativeValueReceived) {
        if (asset == address(0)) {
            require(msg.value >= amount, "400:ValueTooSmall");
            (bool success, ) = to.call{ value: amount }("");
            if (!success) {
                revert("500:TransferFailed");
            }
            return amount;
        } else {
            IERC20(asset).safeTransferFrom(msg.sender, to, amount);
            return 0;
        }
    }

    function transfer(address asset, address to, uint256 amount) internal {
        if (asset == address(0)) {
            (bool success, ) = payable(to).call{ value: amount }("");
            if (!success) {
                revert("500:TransferFailed");
            }
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }

    /// @notice Adds if needed, and returns required value to pass
    /// @param asset Asset to ensure
    /// @param to Spender
    /// @param amount Amount to ensure
    /// @return Native value to pass
    function ensureApproval(
        address asset,
        address to,
        uint256 amount
    ) internal returns (uint256) {
        if (asset != address(0)) {
            uint256 allowance = IERC20(asset).allowance(address(this), to);
            if (allowance < type(uint256).max) {
                IERC20(asset).approve(to, type(uint256).max);
            }
            return 0;
        } else {
            return amount;
        }
    }
}

