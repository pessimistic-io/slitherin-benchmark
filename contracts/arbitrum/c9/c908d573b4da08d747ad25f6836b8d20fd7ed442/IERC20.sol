// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ERC20_IERC20Upgradeable.sol";

/// @title IERC20
/// @notice Interface for the ERC20 token contract
interface IERC20 is IERC20Upgradeable {
    /// @notice Returns the number of decimals used by the token
    /// @return The number of decimals
    function decimals() external view returns (uint8);
}

