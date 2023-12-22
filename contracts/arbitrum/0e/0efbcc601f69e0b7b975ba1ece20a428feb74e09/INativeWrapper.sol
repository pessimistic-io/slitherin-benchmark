// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title INativeWrapper - NativeWrapper interface
/// @dev This contract provides a way to wrap and unwrap Native currency (e.g., ETH)
/// to its ERC20-compatible representation, (e.g., WETH).
interface INativeWrapper {
    // =========================
    // Errors
    // =========================

    /// @notice Thrown when there's insufficient balance in the contract.
    error NativeWrapper_InsufficientBalance();

    // =========================
    // Main functions
    // =========================

    /// @notice Wraps Native currency into its ERC20-compatible representation.
    /// @dev The function sends all the Native currency sent with the call to the wrapped native
    /// currency contract and mints the same amount of WETH to this contract's balance.
    function wrapNative() external payable;

    /// @notice Wraps Native currency into its ERC20-compatible representation
    /// from the vault balance.
    /// @param amount The amount of Native currency to wrap.
    /// @dev The function uses the vault's Native currency balance to mint its
    /// ERC20-compatible representation.
    /// @dev The caller must ensure that the vault has sufficient balance.
    function wrapNativeFromVaultBalance(uint256 amount) external;

    /// @notice Unwraps wrapped Native currency to Native currency.
    /// @param amount The amount of wrapped Native currency to unwrap.
    /// @dev The function burns the specified amount of wrapped Native currency
    /// and sends the same amount of Native currency to this contract's balance.
    /// @dev The caller must ensure that the contract has sufficient WETH balance.
    function unwrapNative(uint256 amount) external;
}

