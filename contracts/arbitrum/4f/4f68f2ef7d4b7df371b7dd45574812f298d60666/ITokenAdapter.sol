// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  ITokenAdapter
/// @author Savvy DeFi
interface ITokenAdapter {
    /// @notice Gets the current version.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Gets the address of the yield token that this adapter supports.
    ///
    /// @return The address of the yield token.
    function token() external view returns (address);

    /// @notice Gets the address of the base token that the yield token wraps.
    ///
    /// @return The address of the base token.
    function baseToken() external view returns (address);

    /// @notice Gets the number of base tokens that a single whole yield token is redeemable for.
    ///
    /// @return The price.
    function price() external view returns (uint256);

    /// @notice Wraps `amount` base tokens into the yield token.
    ///
    /// @param amount           The amount of the base token to wrap.
    /// @param recipient        The address which will receive the yield tokens.
    ///
    /// @return amountYieldTokens The amount of yield tokens minted to `recipient`.
    function wrap(
        uint256 amount,
        address recipient
    ) external returns (uint256 amountYieldTokens);

    /// @notice Unwraps `amount` yield tokens into the base token.
    ///
    /// @param amount           The amount of yield-tokens to redeem.
    /// @param recipient        The recipient of the resulting base tokens.
    ///
    /// @return amountBaseTokens The amount of base tokens unwrapped to `recipient`.
    function unwrap(
        uint256 amount,
        address recipient
    ) external returns (uint256 amountBaseTokens);

    /// @notice Add address of SavvyPositionManager to allowlist
    /// @dev Only owner can call this function/
    /// @param allowlistAddresses The addresses of SavvyPositionManager/YieldStrategyManager.
    /// @param status Status for allowlist. true/false = on/off.
    function addAllowlist(
        address[] memory allowlistAddresses,
        bool status
    ) external;
}

