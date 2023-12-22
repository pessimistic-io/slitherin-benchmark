// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  IERC20TokenReceiver
/// @author Savvy DeFi
interface IERC20TokenReceiver {
    /// @notice Informs implementors of this interface that an ERC20 token has been transferred.
    ///
    /// @param token The token that was transferred.
    /// @param value The amount of the token that was transferred.
    function onERC20Received(address token, uint256 value) external;
}

