// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IWETH9} from "./IWETH9.sol";

import {BaseContract} from "./BaseContract.sol";
import {INativeWrapper} from "./INativeWrapper.sol";

/// @title NativeWrapper
/// @dev This contract provides a way to wrap and unwrap Native currency (e.g., ETH)
/// to its ERC20-compatible representation, (e.g., WETH).
contract NativeWrapper is INativeWrapper, BaseContract {
    IWETH9 private immutable wrappedNative;

    /// @notice Constructs the NativeWrapper contract.
    /// @param _wrappedNative Address of the WETH9 contract.
    constructor(IWETH9 _wrappedNative) {
        wrappedNative = _wrappedNative;
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc INativeWrapper
    function wrapNative() external payable {
        wrappedNative.deposit{value: msg.value}();
    }

    /// @inheritdoc INativeWrapper
    function wrapNativeFromVaultBalance(
        uint256 amount
    ) external onlyOwnerOrVaultItself {
        if (amount > address(this).balance) {
            revert NativeWrapper_InsufficientBalance();
        }
        wrappedNative.deposit{value: amount}();
    }

    /// @inheritdoc INativeWrapper
    function unwrapNative(uint256 amount) external onlyOwnerOrVaultItself {
        uint256 wrappedNativeBalance = wrappedNative.balanceOf(address(this));
        if (amount > wrappedNativeBalance) {
            revert NativeWrapper_InsufficientBalance();
        }

        wrappedNative.withdraw(amount);
    }
}

