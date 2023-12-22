// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IERC20Minimal.sol";

/// @title Interface for WETH9 on Arbitrum
/// @notice token functions to facilitate the wrap and unwrap functions during deposit and withdrawal of WETH token
interface IWETH9 is IERC20Minimal {
    /// @notice Withdraw wrapped ether to get ether to a recipient address
    /// @param recipient address to send unwrapped ether
    /// @param amount amount of WETH to be unwrapped during withdrawal
    function withdrawTo(address recipient, uint256 amount) external;

    /// @notice wrap the ether and transfer to a recipient address
    /// @param recipient address to send wrapped ether
    function depositTo(address recipient) external payable;
}

