// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  ISavvyImmutables
/// @author Savvy DeFi
interface ISavvyImmutables {
    /// @notice Returns the version of the savvy.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Returns the address of the debt token used by the system.
    ///
    /// @return The address of the debt token.
    function debtToken() external view returns (address);
}

