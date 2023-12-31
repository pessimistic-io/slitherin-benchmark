// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.4;

import { IERC20 } from "./IERC20.sol";
import { IWETH9 } from "./IWETH9.sol";

import { SafeTransferLib } from "./libraries_SafeTransferLib.sol";

/// @title   Payment contract
/// @author  https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/PeripheryPayments.sol
/// @notice  Functions to ease deposits and withdrawals of ETH
abstract contract Payment {
    address public immutable WETH9;

    constructor(address _weth9) {
        WETH9 = _weth9;
    }

    receive() external payable {
        require(msg.sender == WETH9, "Not WETH9");
    }

    function unwrapWETH9(uint256 amountMinimum, address recipient) public payable {
        uint256 balanceWETH9 = IWETH9(WETH9).balanceOf(address(this));
        require(balanceWETH9 >= amountMinimum, "Insufficient WETH9");

        if (balanceWETH9 > 0) {
            IWETH9(WETH9).withdraw(balanceWETH9);
            SafeTransferLib.safeTransferETH(recipient, balanceWETH9);
        }
    }

    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) public payable {
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        require(balanceToken >= amountMinimum, "Insufficient token");

        if (balanceToken > 0) {
            SafeTransferLib.safeTransfer(token, recipient, balanceToken);
        }
    }

    function refundETH() external payable {
        if (address(this).balance > 0) SafeTransferLib.safeTransferETH(msg.sender, address(this).balance);
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            IWETH9(WETH9).deposit{ value: value }(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            SafeTransferLib.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            SafeTransferLib.safeTransferFrom(token, payer, recipient, value);
        }
    }
}

