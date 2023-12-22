// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "./sd59x18_Constants.sol";
import "./Config.sol";
import "./SafeTransferLib.sol";
import "./ERC20.sol";

/**
 * @title Performs various operations around the payment of eth and tokens
 */
library Payments {
    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    error InsufficientETH();

    /// @notice Pays an amount of ETH or ERC20 to a recipient
    /// @param token The token to pay (can be ETH using Constants.ETH)
    /// @param recipient The address that will receive the payment
    /// @param value The amount to pay
    function pay(address token, address recipient, uint256 value) internal {
        if (token == Constants.ETH) {
            recipient.safeTransferETH(value);
        } else {
            if (value == Constants.CONTRACT_BALANCE) {
                value = IERC20(token).balanceOf(address(this));
            }

            ERC20(token).safeTransfer(recipient, value);
        }
    }

    /// @notice Approves CORE to spend ERC20s in the router
    /// @param token The token to approve
    /// @param value amount approved to spend
    function approveERC20Core(address token, uint256 value) internal {
        // set approval
        ERC20(token).safeApprove(Config.load().VOLTZ_V2_CORE_PROXY, value);
    }

    /// @notice Wraps an amount of ETH into WETH
    /// @param recipient The recipient of the WETH
    /// @param amount The amount to wrap (can be CONTRACT_BALANCE)
    function wrapETH(address recipient, uint256 amount) internal {
        if (amount == Constants.CONTRACT_BALANCE) {
            amount = address(this).balance;
        } else if (amount > address(this).balance) {
            revert InsufficientETH();
        }
        if (amount > 0) {
            Config.load().WETH9.deposit{value: amount}();
            if (recipient != address(this)) {
                Config.load().WETH9.transfer(recipient, amount);
            }
        }
    }

    /// @notice Unwraps all of the contract's WETH into ETH
    /// @param recipient The recipient of the ETH
    /// @param amountMinimum The minimum amount of ETH desired
    function unwrapWETH9(address recipient, uint256 amountMinimum) internal {
        uint256 value = Config.load().WETH9.balanceOf(address(this));
        if (value < amountMinimum) {
            revert InsufficientETH();
        }
        if (value > 0) {
            Config.load().WETH9.withdraw(value);
            if (recipient != address(this)) {
                recipient.safeTransferETH(value);
            }
        }
    }
}

